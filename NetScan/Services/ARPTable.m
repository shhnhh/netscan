#import "ARPTable.h"

#include <sys/param.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <netinet/in.h>
#include <arpa/inet.h>

// RTF_LLINFO selects the routing-table entries that carry link-layer (ARP)
// info. Newer SDKs have quietly dropped the constant even though the kernel
// still honours the value, so fall back to its well-known bit if the header
// no longer defines it.
#ifndef RTF_LLINFO
#define RTF_LLINFO 0x400
#endif

// Route messages pack their sockaddrs back-to-back, each padded up to a
// 4-byte boundary. This is the same rounding Apple's own network_cmds/arp.c
// uses to step from one sockaddr to the next.
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
        struct rt_msghdr *rtm = (struct rt_msghdr *)next;
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

@end
