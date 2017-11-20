#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    NSLog(@"trx updatedTransactions");
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSLog(@"trx failed");

                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    callback(@[RCTJSErrorFromNSError(transaction.error)]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state failed.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }

            case SKPaymentTransactionStateRestored:
                NSLog(@"trx Restored.");
            case SKPaymentTransactionStatePurchased: {
                NSLog(@"trx purchased");

                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    NSDictionary *purchase = @{
                                              @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                                              @"transactionIdentifier": transaction.transactionIdentifier,
                                              @"productIdentifier": transaction.payment.productIdentifier,
                                              @"transactionReceipt": [[transaction transactionReceipt] base64EncodedStringWithOptions:0],
                                              @"transactionIdentifier": transaction.transactionIdentifier
                                              };
                    callback(@[[NSNull null], purchase]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"No callback registered for transaction with state purchased.");
                }
                // To be handle via finishTransaction in javascript side.
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"trx purchasing");
                break;
            case SKPaymentTransactionStateDeferred:
                NSLog(@"trx deferred");
                break;
            default:
                NSLog(@"trx default");
                break;
        }
    }
}
- (void)paymentQueue:(SKPaymentQueue *)queue
 removedTransactions:(NSArray *)transactions
{
    NSLog(@"trx Removed transaction");
}

RCT_EXPORT_METHOD(purchaseProductForUser:(NSString *)productIdentifier
                  quantity:(nonnull NSInteger *)quantity
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier quantity:quantity username:username callback:callback];
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  quantity:(nonnull NSInteger *)quantity
                  callback:(RCTResponseSenderBlock)callback)
{
    [self doPurchaseProduct:productIdentifier quantity:quantity username:nil callback:callback];
}

- (void) doPurchaseProduct:(NSString *)productIdentifier
                  quantity:(nonnull NSInteger *)quantity
                  username:(NSString *)username
                  callback:(RCTResponseSenderBlock)callback
{
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }

    if(product) {
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
        if (quantity) {
            payment.quantity = quantity;
        }
        if(username) {
            payment.applicationUsername = username;
        }
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSLog(@"trx restore completed transactions failed with error");
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        switch (error.code)
        {
            case SKErrorPaymentCancelled:
                callback(@[@"user_cancelled"]);
                break;
            default:
                callback(@[@"restore_failed"]);
                break;
        }

        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSLog(@"trx restore completed transaction finished");
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKPaymentTransaction *transaction in queue.transactions){
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {

                NSMutableDictionary *purchase = [NSMutableDictionary dictionaryWithDictionary: @{
                    @"transactionDate": @(transaction.transactionDate.timeIntervalSince1970 * 1000),
                    @"transactionIdentifier": transaction.transactionIdentifier,
                    @"productIdentifier": transaction.payment.productIdentifier,
                    @"transactionReceipt": [[transaction transactionReceipt] base64EncodedStringWithOptions:0]
                }];

                SKPaymentTransaction *originalTransaction = transaction.originalTransaction;
                if (originalTransaction) {
                    purchase[@"originalTransactionDate"] = @(originalTransaction.transactionDate.timeIntervalSince1970 * 1000);
                    purchase[@"originalTransactionIdentifier"] = originalTransaction.transactionIdentifier;
                }

                [productsArrayForJS addObject:purchase];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(restorePurchasesForUser:(NSString *)username
                    callback:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    if(!username) {
        callback(@[@"username_required"]);
        return;
    }
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactionsWithApplicationUsername:username];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    if([SKPaymentQueue canMakePayments]){
        SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                              initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
        productsRequest.delegate = self;
        _callbacks[RCTKeyForInstance(productsRequest)] = callback;
        [productsRequest start];
    } else {
        callback(@[@"not_available"]);
    }
}

RCT_EXPORT_METHOD(canMakePayments: (RCTResponseSenderBlock)callback)
{
    BOOL canMakePayments = [SKPaymentQueue canMakePayments];
    callback(@[@(canMakePayments)]);
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
      callback(@[@"not_available"]);
    } else {
      callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

RCT_EXPORT_METHOD(finishTransaction:(NSString *)transactionIdentifier)
{
    NSLog(@"trx finishTransaction");
    SKPaymentQueue *queue = [SKPaymentQueue defaultQueue];
    for(SKPaymentTransaction *transaction in queue.transactions){
        if(transaction.transactionIdentifier == transactionIdentifier && transaction.transactionState == SKPaymentTransactionStatePurchased) {
            [queue finishTransaction:transaction];
            return;
        }
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"countryCode": [item.priceLocale objectForKey: NSLocaleCountryCode],
                                      @"downloadable": item.downloadable ? @"true" : @"false" ,
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      };
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

// SKProductsRequestDelegate network error
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if(callback) {
        callback(@[RCTJSErrorFromNSError(error)]);
        [_callbacks removeObjectForKey:key];
    }
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

@end
