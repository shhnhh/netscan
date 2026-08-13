#import "ARPTable.h"

#include <sys/param.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// The iOS SDK ships <net/if_dl.h> (sockaddr_dl) and the routing sysctl MIB,
// but deliberately does NOT ship <net/route.h> — so the routing-message
// struct and flags it would normally provide are declared here by hand. This
// is the kernel's long-stable PF_ROUTE ABI; the layout mirrors XNU's
// bsd/net/route.h exactly so the byte offsets line up with what the kernel
// writes into the sysctl buffer. (This is the same "bring the header
// yourself" workaround the open-source MMLanScan/MacFinder use, minus the
// dependency on copying Apple's macOS SDK files into the repo.)
#ifndef NET_RT_FLAGS
#define NET_RT_FLAGS 2
#endif

#ifndef RTF_LLINFO
#define RTF_LLINFO 0x400
#endif

#ifndef NET_RT_DUMP
#define NET_RT_DUMP 1
#endif

#ifndef RTF_GATEWAY
#define RTF_GATEWAY 0x2
#endif

#ifndef RTA_DST
#define RTA_DST 0x1
#endif

#ifndef RTA_GATEWAY
#define RTA_GATEWAY 0x2
#endif

struct netscan_rt_metrics {
    u_int32_t rmx_locks;
    u_int32_t rmx_mtu;
    u_int32_t rmx_hopcount;
    int32_t   rmx_expire;
    u_int32_t rmx_recvpipe;
    u_int32_t rmx_sendpipe;
    u_int32_t rmx_ssthresh;
    u_int32_t rmx_rtt;
    u_int32_t rmx_rttvar;
    u_int32_t rmx_pksent;
    u_int32_t rmx_state;
    u_int32_t rmx_filler[3];
};

struct netscan_rt_msghdr {
    u_short   rtm_msglen;
    u_char    rtm_version;
    u_char    rtm_type;
    u_short   rtm_index;
    int       rtm_flags;
    int       rtm_addrs;
    pid_t     rtm_pid;
    int       rtm_seq;
    int       rtm_errno;
    int       rtm_use;
    u_int32_t rtm_inits;
    struct netscan_rt_metrics rtm_rmx;
};

// Route messages pack their sockaddrs back-to-back, each padded up to a
// 4-byte boundary. Same rounding Apple's own network_cmds/arp.c uses to step
// from one sockaddr to the next.
#define NETSCAN_SA_SIZE(sa)                                              \
    ((!(sa) || ((struct sockaddr *)(sa))->sa_len == 0)                   \
        ? sizeof(uint32_t)                                               \
        : 1 + ((((struct sockaddr *)(sa))->sa_len - 1) | (sizeof(uint32_t) - 1)))

@implementation ARPTable

+ (NSDictionary<NSString *, NSString *> *)currentTable {
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionary];

    int mib[6];
    mib[0] = CTL_NET;
    mib[1] = PF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_INET;
    mib[4] = NET_RT_FLAGS;
    mib[5] = RTF_LLINFO;

    size_t needed = 0;
    if (sysctl(mib, 6, NULL, &needed, NULL, 0) < 0 || needed == 0) {
        return result;
    }

    char *buf = malloc(needed);
    if (buf == NULL) {
        return result;
    }
    if (sysctl(mib, 6, buf, &needed, NULL, 0) < 0) {
        free(buf);
        return result;
    }

    char *lim = buf + needed;
    char *next = buf;
    while (next < lim) {
        struct netscan_rt_msghdr *rtm = (struct netscan_rt_msghdr *)next;
        if (rtm->rtm_msglen == 0) {
            break; // defensive: avoid an infinite loop on a malformed record
        }

        struct sockaddr_in *sin = (struct sockaddr_in *)(rtm + 1);
        struct sockaddr_dl *sdl = (struct sockaddr_dl *)((char *)sin + NETSCAN_SA_SIZE(sin));

        if (sdl->sdl_family == AF_LINK && sdl->sdl_alen == 6) {
            unsigned char *mac = (unsigned char *)LLADDR(sdl);
            if (mac[0] || mac[1] || mac[2] || mac[3] || mac[4] || mac[5]) {
                char ipstr[INET_ADDRSTRLEN];
                if (inet_ntop(AF_INET, &sin->sin_addr, ipstr, sizeof(ipstr))) {
                    NSString *ip = [NSString stringWithUTF8String:ipstr];
                    NSString *macString = [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
                                           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]];
                    if (ip != nil) {
                        result[ip] = macString;
                    }
                }
            }
        }

        next += rtm->rtm_msglen;
    }

    free(buf);
    return result;
}

+ (nullable NSString *)defaultGatewayIPv4 {
    int mib[6];
    mib[0] = CTL_NET;
    mib[1] = PF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_INET;
    mib[4] = NET_RT_DUMP;
    mib[5] = 0;

    size_t needed = 0;
    if (sysctl(mib, 6, NULL, &needed, NULL, 0) < 0 || needed == 0) {
        return nil;
    }

    char *buf = malloc(needed);
    if (buf == NULL) {
        return nil;
    }
    if (sysctl(mib, 6, buf, &needed, NULL, 0) < 0) {
        free(buf);
        return nil;
    }

    NSString *gateway = nil;
    char *lim = buf + needed;
    char *next = buf;
    while (next < lim) {
        struct netscan_rt_msghdr *rtm = (struct netscan_rt_msghdr *)next;
        if (rtm->rtm_msglen == 0) {
            break;
        }

        // The default route is the one whose destination is 0.0.0.0 and
        // which carries a gateway (RTF_GATEWAY) rather than pointing
        // straight at an interface. Destination is always the first
        // sockaddr present; the gateway sockaddr immediately follows it
        // when RTA_GATEWAY is set, which it is for every gateway route.
        if ((rtm->rtm_flags & RTF_GATEWAY) &&
            (rtm->rtm_addrs & RTA_DST) &&
            (rtm->rtm_addrs & RTA_GATEWAY)) {
            struct sockaddr *dstSa = (struct sockaddr *)(rtm + 1);
            struct sockaddr_in *dst = (struct sockaddr_in *)dstSa;
            if (dst->sin_family == AF_INET && dst->sin_addr.s_addr == INADDR_ANY) {
                struct sockaddr *gwSa = (struct sockaddr *)((char *)dstSa + NETSCAN_SA_SIZE(dstSa));
                if (gwSa->sa_family == AF_INET) {
                    struct sockaddr_in *gw = (struct sockaddr_in *)gwSa;
                    char ipstr[INET_ADDRSTRLEN];
                    if (inet_ntop(AF_INET, &gw->sin_addr, ipstr, sizeof(ipstr))) {
                        gateway = [NSString stringWithUTF8String:ipstr];
                    }
                }
            }
        }

        next += rtm->rtm_msglen;
        if (gateway != nil) {
            break;
        }
    }

    free(buf);
    return gateway;
}

@end
