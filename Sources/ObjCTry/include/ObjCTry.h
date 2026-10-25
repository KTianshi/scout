#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the reason of any Objective-C exception it raised (nil if none). Swift can't catch these,
/// and one unwinding through Swift code leaves the runtime corrupted (Scout crashed seconds later, somewhere else).
NSString *_Nullable LKCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
