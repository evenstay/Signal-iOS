//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSThread.h"
#import "AppReadiness.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSReadTracking.h"
#import "TSAccountManager.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInteraction.h"
#import "TSInvalidIdentityKeyReceivingErrorMessage.h"
#import "TSOutgoingMessage.h"
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@import Intents;

NS_ASSUME_NONNULL_BEGIN

@interface TSThread ()

@property (nonatomic) TSThreadStoryViewMode storyViewMode;
@property (nonatomic, nullable) NSNumber *lastSentStoryTimestamp;

@property (nonatomic, nullable) NSDate *creationDate;
@property (nonatomic) BOOL isArchivedObsolete;
@property (nonatomic) BOOL isMarkedUnreadObsolete;

@property (nonatomic, copy, nullable) NSString *messageDraft;
@property (nonatomic, nullable) MessageBodyRanges *messageDraftBodyRanges;

@property (atomic) uint64_t mutedUntilTimestampObsolete;
@property (nonatomic) uint64_t lastInteractionRowId;

@property (nonatomic, nullable) NSDate *mutedUntilDateObsolete;
@property (nonatomic) uint64_t lastVisibleSortIdObsolete;
@property (nonatomic) double lastVisibleSortIdOnScreenPercentageObsolete;

@property (nonatomic) TSThreadMentionNotificationMode mentionNotificationMode;

@end

#pragma mark -

@implementation TSThread

+ (NSString *)collection {
    return @"TSThread";
}

+ (TSFTSIndexMode)FTSIndexMode
{
    return TSFTSIndexModeManualUpdates;
}

- (instancetype)init
{
    self = [super init];

    if (self) {
        _conversationColorNameObsolete = @"Obsolete";
    }

    return self;
}

- (instancetype)initWithUniqueId:(NSString *)uniqueId
{
    self = [super initWithUniqueId:uniqueId];

    if (self) {
        _creationDate    = [NSDate date];
        _messageDraft    = nil;
        _conversationColorNameObsolete = @"Obsolete";
    }

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
   conversationColorNameObsolete:(NSString *)conversationColorNameObsolete
                    creationDate:(nullable NSDate *)creationDate
             editTargetTimestamp:(nullable NSNumber *)editTargetTimestamp
              isArchivedObsolete:(BOOL)isArchivedObsolete
          isMarkedUnreadObsolete:(BOOL)isMarkedUnreadObsolete
            lastInteractionRowId:(uint64_t)lastInteractionRowId
          lastSentStoryTimestamp:(nullable NSNumber *)lastSentStoryTimestamp
       lastVisibleSortIdObsolete:(uint64_t)lastVisibleSortIdObsolete
lastVisibleSortIdOnScreenPercentageObsolete:(double)lastVisibleSortIdOnScreenPercentageObsolete
         mentionNotificationMode:(TSThreadMentionNotificationMode)mentionNotificationMode
                    messageDraft:(nullable NSString *)messageDraft
          messageDraftBodyRanges:(nullable MessageBodyRanges *)messageDraftBodyRanges
          mutedUntilDateObsolete:(nullable NSDate *)mutedUntilDateObsolete
     mutedUntilTimestampObsolete:(uint64_t)mutedUntilTimestampObsolete
           shouldThreadBeVisible:(BOOL)shouldThreadBeVisible
                   storyViewMode:(TSThreadStoryViewMode)storyViewMode
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _conversationColorNameObsolete = conversationColorNameObsolete;
    _creationDate = creationDate;
    _editTargetTimestamp = editTargetTimestamp;
    _isArchivedObsolete = isArchivedObsolete;
    _isMarkedUnreadObsolete = isMarkedUnreadObsolete;
    _lastInteractionRowId = lastInteractionRowId;
    _lastSentStoryTimestamp = lastSentStoryTimestamp;
    _lastVisibleSortIdObsolete = lastVisibleSortIdObsolete;
    _lastVisibleSortIdOnScreenPercentageObsolete = lastVisibleSortIdOnScreenPercentageObsolete;
    _mentionNotificationMode = mentionNotificationMode;
    _messageDraft = messageDraft;
    _messageDraftBodyRanges = messageDraftBodyRanges;
    _mutedUntilDateObsolete = mutedUntilDateObsolete;
    _mutedUntilTimestampObsolete = mutedUntilTimestampObsolete;
    _shouldThreadBeVisible = shouldThreadBeVisible;
    _storyViewMode = storyViewMode;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    // renamed `hasEverHadMessage` -> `shouldThreadBeVisible`
    if (!_shouldThreadBeVisible) {
        NSNumber *_Nullable legacy_hasEverHadMessage = [coder decodeObjectForKey:@"hasEverHadMessage"];

        if (legacy_hasEverHadMessage != nil) {
            _shouldThreadBeVisible = legacy_hasEverHadMessage.boolValue;
        }
    }

    if (_conversationColorNameObsolete.length == 0) {
        _conversationColorNameObsolete = @"Obsolete";
    }

    NSDate *_Nullable lastMessageDate = [coder decodeObjectOfClass:NSDate.class forKey:@"lastMessageDate"];
    NSDate *_Nullable archivalDate = [coder decodeObjectOfClass:NSDate.class forKey:@"archivalDate"];
    _isArchivedByLegacyTimestampForSorting =
        [self.class legacyIsArchivedWithLastMessageDate:lastMessageDate archivalDate:archivalDate];

    if ([coder decodeObjectForKey:@"archivedAsOfMessageSortId"] != nil) {
        OWSAssertDebug(!_isArchivedObsolete);
        _isArchivedObsolete = YES;
    }

    return self;
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [ThreadAssociatedData createFor:self.uniqueId warnIfPresent:YES transaction:transaction];

    if (self.shouldThreadBeVisible && ![SSKPreferences hasSavedThreadWithTransaction:transaction]) {
        [SSKPreferences setHasSavedThread:YES transaction:transaction];
    }

    [self.modelReadCaches.threadReadCache didInsertOrUpdateThread:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    if (self.shouldThreadBeVisible && ![SSKPreferences hasSavedThreadWithTransaction:transaction]) {
        [SSKPreferences setHasSavedThread:YES transaction:transaction];
    }

    [self.modelReadCaches.threadReadCache didInsertOrUpdateThread:self transaction:transaction];

    [PinnedThreadManager handleUpdatedThread:self transaction:transaction];
}

- (void)anyWillRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillRemoveWithTransaction:transaction];
    OWSFail(@"Not supported.");
}

- (void)removeAllThreadInteractionsWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    // We can't safely delete interactions while enumerating them, so
    // we collect and delete separately.
    //
    // We don't want to instantiate the interactions when collecting them
    // or when deleting them.
    NSMutableArray<NSString *> *interactionIds = [NSMutableArray new];
    NSError *error;
    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:self.uniqueId];
    [interactionFinder enumerateInteractionIdsWithTransaction:transaction
                                                        error:&error
                                                        block:^(NSString *key, BOOL *stop) {
                                                            [interactionIds addObject:key];
                                                        }];
    if (error != nil) {
        OWSFailDebug(@"Error during enumeration: %@", error);
    }

    [transaction ignoreInteractionUpdatesForThreadUniqueId:self.uniqueId];
    
    for (NSString *interactionId in interactionIds) {
        // We need to fetch each interaction, since [TSInteraction removeWithTransaction:] does important work.
        TSInteraction *_Nullable interaction =
            [TSInteraction anyFetchWithUniqueId:interactionId transaction:transaction];
        if (!interaction) {
            OWSFailDebug(@"couldn't load thread's interaction for deletion.");
            continue;
        }
        [interaction anyRemoveWithTransaction:transaction];
    }

    // As an optimization, we called `ignoreInteractionUpdatesForThreadUniqueId` so as not
    // to re-save the thread after *each* interaction deletion. However, we still need to resave
    // the thread just once, after all the interactions are deleted.
    [self anyUpdateWithTransaction:transaction
                             block:^(TSThread *thread) {
                                 thread.lastInteractionRowId = 0;
                             }];
}

- (BOOL)isNoteToSelf
{
    return NO;
}

- (NSString *)colorSeed
{
    return self.uniqueId;
}

#pragma mark - To be subclassed.

- (NSArray<SignalServiceAddress *> *)recipientAddressesWithSneakyTransaction
{
    __block NSArray<SignalServiceAddress *> *recipientAddresses;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        recipientAddresses = [self recipientAddressesWithTransaction:transaction];
    }];
    return recipientAddresses;
}


- (NSArray<SignalServiceAddress *> *)recipientAddressesWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAbstractMethod();

    return @[];
}

- (BOOL)hasSafetyNumbers
{
    return NO;
}

#pragma mark - Interactions

/**
 * Iterate over this thread's interactions.
 */
- (void)enumerateRecentInteractionsWithTransaction:(SDSAnyReadTransaction *)transaction
                                        usingBlock:(void (^)(TSInteraction *interaction))block
{
    NSError *error;
    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:self.uniqueId];
    [interactionFinder enumerateRecentInteractionsWithTransaction:transaction
                                                            error:&error
                                                            block:^(TSInteraction *interaction, BOOL *stop) {
                                                                block(interaction);
                                                            }];
    if (error != nil) {
        OWSFailDebug(@"Error during enumeration: %@", error);
    }
}

- (NSArray<TSInvalidIdentityKeyReceivingErrorMessage *> *)receivedMessagesForInvalidKey:(NSData *)key
                                                                                     tx:(SDSAnyReadTransaction *)tx
{
    NSMutableArray *errorMessages = [NSMutableArray new];
    [self enumerateRecentInteractionsWithTransaction:tx
                                          usingBlock:^(TSInteraction *interaction) {
                                              if ([interaction isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage
                                                                                 class]]) {
                                                  TSInvalidIdentityKeyReceivingErrorMessage *error
                                                      = (TSInvalidIdentityKeyReceivingErrorMessage *)interaction;
                                                  @try {
                                                      if ([[error throws_newIdentityKey] isEqualToData:key]) {
                                                          [errorMessages
                                                              addObject:(TSInvalidIdentityKeyReceivingErrorMessage *)
                                                                            interaction];
                                                      }
                                                  } @catch (NSException *exception) {
                                                      OWSFailDebug(@"exception: %@", exception);
                                                  }
                                              }
                                          }];

    return errorMessages;
}

- (nullable TSInteraction *)lastInteractionForInboxWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    return [[[InteractionFinder alloc] initWithThreadUniqueId:self.uniqueId]
        mostRecentInteractionForInboxWithTransaction:transaction];
}

- (nullable TSInteraction *)firstInteractionAtOrAroundSortId:(uint64_t)sortId
                                                 transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    return
        [[[InteractionFinder alloc] initWithThreadUniqueId:self.uniqueId] firstInteractionAtOrAroundSortId:sortId
                                                                                               transaction:transaction];
}

- (void)updateWithInsertedMessage:(TSInteraction *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    [self updateWithMessage:message wasMessageInserted:YES transaction:transaction];
}

- (void)updateWithUpdatedMessage:(TSInteraction *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    [self updateWithMessage:message wasMessageInserted:NO transaction:transaction];
}

- (uint64_t)messageSortIdForMessage:(TSInteraction *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    if (message.grdbId == nil) {
        OWSFailDebug(@"Missing messageSortId.");
    } else if (message.grdbId.unsignedLongLongValue == 0) {
        OWSFailDebug(@"Invalid messageSortId.");
    } else {
        return message.grdbId.unsignedLongLongValue;
    }
    return 0;
}

- (void)updateWithMessage:(TSInteraction *)message
       wasMessageInserted:(BOOL)wasMessageInserted
              transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(transaction != nil);

    BOOL hasLastVisibleInteraction = [self hasLastVisibleInteractionWithTransaction:transaction];
    BOOL needsToClearLastVisibleSortId = hasLastVisibleInteraction && wasMessageInserted;

    if (![message shouldAppearInInboxWithTransaction:transaction]) {
        // We want to clear the last visible sort ID on any new message,
        // even if the message doesn't appear in the inbox view.
        if (needsToClearLastVisibleSortId) {
            [self clearLastVisibleInteractionWithTransaction:transaction];
        }
        [self scheduleTouchFinalizationWithTransaction:transaction];
        return;
    }

    uint64_t messageSortId = [self messageSortIdForMessage:message transaction:transaction];
    BOOL needsToMarkAsVisible = !self.shouldThreadBeVisible;

    ThreadAssociatedData *associatedData = [ThreadAssociatedData fetchOrDefaultForThread:self transaction:transaction];

    BOOL needsToClearArchived = [self shouldClearArchivedStatusWhenUpdatingWithMessage:message
                                                                    wasMessageInserted:wasMessageInserted
                                                                  threadAssociatedData:associatedData
                                                                           transaction:transaction];

    BOOL needsToUpdateLastInteractionRowId = messageSortId > self.lastInteractionRowId;

    BOOL needsToClearIsMarkedUnread = associatedData.isMarkedUnread && wasMessageInserted;

    if (needsToMarkAsVisible || needsToClearArchived || needsToUpdateLastInteractionRowId
        || needsToClearLastVisibleSortId || needsToClearIsMarkedUnread) {
        [self anyUpdateWithTransaction:transaction
                                 block:^(TSThread *thread) {
                                     thread.shouldThreadBeVisible = YES;
                                     thread.lastInteractionRowId = MAX(thread.lastInteractionRowId, messageSortId);
                                 }];
        [associatedData clearIsArchived:needsToClearArchived
                    clearIsMarkedUnread:needsToClearIsMarkedUnread
                   updateStorageService:YES
                            transaction:transaction];
        if (needsToMarkAsVisible) {
            // Non-visible threads don't get indexed, so if we're becoming visible for the first time...
            [SDSDatabaseStorage.shared touchThread:self shouldReindex:true transaction:transaction];
        }
        if (needsToClearLastVisibleSortId) {
            [self clearLastVisibleInteractionWithTransaction:transaction];
        }
    } else {
        [self scheduleTouchFinalizationWithTransaction:transaction];
    }
}

- (BOOL)shouldClearArchivedStatusWhenUpdatingWithMessage:(TSInteraction *)message
                                      wasMessageInserted:(BOOL)wasMessageInserted
                                    threadAssociatedData:(ThreadAssociatedData *)threadAssociatedData
                                             transaction:(SDSAnyReadTransaction *)transaction
{
    BOOL needsToClearArchived = threadAssociatedData.isArchived && wasMessageInserted;

    // Shouldn't clear archived during migrations.
    if (!CurrentAppContext().isRunningTests && !AppReadiness.isAppReady) {
        needsToClearArchived = NO;
    }

    // Shouldn't clear archived during thread import.
    if ([message isKindOfClass:TSInfoMessage.class]
        && ((TSInfoMessage *)message).messageType == TSInfoMessageSyncedThread) {
        needsToClearArchived = NO;
    }

    // Shouldn't clear archived if:
    // - The thread is muted.
    // - The user has requested we keep muted chats archived.
    // - The message was sent by someone other than the current user. (If the
    //   current user sent the message, we should clear archived.)
    {
        BOOL threadIsMuted = threadAssociatedData.isMuted;
        BOOL shouldKeepMutedChatsArchived = [SSKPreferences shouldKeepMutedChatsArchivedWithTransaction:transaction];
        BOOL wasMessageSentByUs = [message isKindOfClass:[TSOutgoingMessage class]];
        if (threadIsMuted && shouldKeepMutedChatsArchived && !wasMessageSentByUs) {
            needsToClearArchived = NO;
        }
    }

    return needsToClearArchived;
}

- (void)updateWithRemovedMessage:(TSInteraction *)message transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(message != nil);
    OWSAssertDebug(transaction != nil);

    uint64_t messageSortId = [self messageSortIdForMessage:message transaction:transaction];
    BOOL needsToUpdateLastInteractionRowId = messageSortId == self.lastInteractionRowId;

    NSNumber *_Nullable lastVisibleSortId = [self lastVisibleSortIdWithTransaction:transaction];
    BOOL needsToUpdateLastVisibleSortId
        = (lastVisibleSortId != nil && lastVisibleSortId.unsignedLongLongValue == messageSortId);

    if (needsToUpdateLastInteractionRowId || needsToUpdateLastVisibleSortId) {
        [self anyUpdateWithTransaction:transaction
                                 block:^(TSThread *thread) {
                                     if (needsToUpdateLastInteractionRowId) {
                                         TSInteraction *_Nullable latestInteraction =
                                             [thread lastInteractionForInboxWithTransaction:transaction];
                                         thread.lastInteractionRowId = latestInteraction ? latestInteraction.sortId : 0;
                                     }
                                 }];

        if (needsToUpdateLastVisibleSortId) {
            TSInteraction *_Nullable messageBeforeDeletedMessage =
                [self firstInteractionAtOrAroundSortId:lastVisibleSortId.unsignedLongLongValue transaction:transaction];
            if (messageBeforeDeletedMessage != nil) {
                [self setLastVisibleInteractionWithSortId:messageBeforeDeletedMessage.sortId
                                       onScreenPercentage:1
                                              transaction:transaction];
            } else {
                [self clearLastVisibleInteractionWithTransaction:transaction];
            }
        }
    } else {
        [self scheduleTouchFinalizationWithTransaction:transaction];
    }
}

- (void)scheduleTouchFinalizationWithTransaction:(SDSAnyWriteTransaction *)transactionForMethod
{
    OWSAssertDebug(transactionForMethod != nil);

    // If we insert, update or remove N interactions in a given
    // transactions, we don't need to touch the same thread more
    // than once.
    [transactionForMethod addTransactionFinalizationBlockForKey:self.transactionFinalizationKey
                                                          block:^(SDSAnyWriteTransaction *transactionForBlock) {
                                                              [self.databaseStorage touchThread:self
                                                                                  shouldReindex:NO
                                                                                    transaction:transactionForBlock];
                                                          }];
}

- (void)softDeleteThreadWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    OWSLogInfo(@"Soft deleting thread with ID %@", self.uniqueId);

    [self removeAllThreadInteractionsWithTransaction:transaction];
    [self anyUpdateWithTransaction:transaction
                             block:^(TSThread *thread) {
                                 thread.messageDraft = nil;
                                 thread.shouldThreadBeVisible = NO;
                                 [ThreadReplyInfoObjC deleteWithThreadUniqueId:thread.uniqueId tx:transaction];
                             }];

    // Delete any intents we previously donated for this thread.
    [INInteraction deleteInteractionsWithGroupIdentifier:self.uniqueId completion:^(NSError *error) {}];
}

- (BOOL)hasPendingMessageRequestWithTransaction:(GRDBReadTransaction *)transaction
{
    return [GRDBThreadFinder hasPendingMessageRequestWithThread:self transaction:transaction];
}

#pragma mark - Archival

+ (BOOL)legacyIsArchivedWithLastMessageDate:(nullable NSDate *)lastMessageDate
                               archivalDate:(nullable NSDate *)archivalDate
{
    if (!archivalDate) {
        return NO;
    }

    if (!lastMessageDate) {
        return YES;
    }

    return [archivalDate compare:lastMessageDate] != NSOrderedAscending;
}

- (void)updateWithDraft:(nullable MessageBody *)draftMessageBody
              replyInfo:(nullable ThreadReplyInfoObjC *)replyInfo
    editTargetTimestamp:(nullable NSNumber *)editTargetTimestamp
            transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSThread *thread) {
                                 thread.messageDraft = draftMessageBody.text;
                                 thread.messageDraftBodyRanges = draftMessageBody.ranges;
                                 thread.editTargetTimestamp = editTargetTimestamp;
                             }];
    if (replyInfo != nil) {
        [replyInfo saveWithThreadUniqueId:self.uniqueId tx:transaction];
    } else {
        [ThreadReplyInfoObjC deleteWithThreadUniqueId:self.uniqueId tx:transaction];
    }
}

- (void)updateWithMentionNotificationMode:(TSThreadMentionNotificationMode)mentionNotificationMode
                              transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSThread *thread) {
                                 thread.mentionNotificationMode = mentionNotificationMode;
                             }];
}

- (void)updateWithShouldThreadBeVisible:(BOOL)shouldThreadBeVisible transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSThread *thread) { thread.shouldThreadBeVisible = shouldThreadBeVisible; }];
}

- (void)updateWithLastSentStoryTimestamp:(nullable NSNumber *)lastSentStoryTimestamp
                             transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction
                             block:^(TSThread *thread) {
                                 if (lastSentStoryTimestamp.unsignedIntegerValue
                                     > thread.lastSentStoryTimestamp.unsignedIntegerValue) {
                                     thread.lastSentStoryTimestamp = lastSentStoryTimestamp;
                                 }
                             }];
}

- (void)updateWithStoryViewMode:(TSThreadStoryViewMode)storyViewMode transaction:(SDSAnyWriteTransaction *)transaction
{
    [self anyUpdateWithTransaction:transaction block:^(TSThread *thread) { thread.storyViewMode = storyViewMode; }];
}

#pragma mark - Merging

- (void)mergeFrom:(TSThread *)otherThread
{
    self.shouldThreadBeVisible = self.shouldThreadBeVisible || otherThread.shouldThreadBeVisible;
    self.lastInteractionRowId = MAX(self.lastInteractionRowId, otherThread.lastInteractionRowId);

    // Copy the draft if this thread doesn't have one. We always assign both
    // values if we assign one of them since they're related.
    if (self.messageDraft == nil) {
        self.messageDraft = otherThread.messageDraft;
        self.messageDraftBodyRanges = otherThread.messageDraftBodyRanges;
    }
}

@end

NS_ASSUME_NONNULL_END
