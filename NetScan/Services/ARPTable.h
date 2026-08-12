#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads the kernel's ARP cache (IPv4 -> hardware/MAC address) the same way
/// the `arp -a` command does: a sysctl PF_ROUTE / NET_RT_FLAGS / RTF_LLINFO
/// dump of the routing table's link-layer entries.
///
/// This lives in Objective-C on purpose. The types this needs — struct
/// rt_msghdr, struct sockaddr_dl, the RTF_LLINFO flag — exist in the iOS C
/// SDK headers (<net/route.h>, <net/if_dl.h>) but are NOT surfaced to Swift's
/// Darwin overlay, which is why a pure-Swift attempt failed to compile. From
/// C they're all available.
///
/// Only returns entries the kernel currently has cached. The cache is
/// populated as a side effect of actually talking to a host (ping / TCP
/// connect), which the scan already does for every address — so a MAC shows
/// up here shortly after that host has been probed.
@interface ARPTable : NSObject

/// Keys are dotted-quad IPv4 strings, values are lowercase colon-separated
/// MAC strings ("a4:83:e7:1c:22:0d"). All-zero addresses are filtered out.
+ (NSDictionary<NSString *, NSString *> *)currentTable;

@end

NS_ASSUME_NONNULL_END
