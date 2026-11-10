// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Parameter addresses.
///
/// 0...144 are the unpacked DX7 voice parameters (the same offsets a DX7
/// single-voice SysEx dump uses), 160...165 switch operators 1...6 on and
/// off, and 200... are the effect and master parameters below.
typedef NS_ENUM(AUParameterAddress, OpenFMAddress) {
    OpenFMAddressOperatorEnable = 160,
    OpenFMAddressChorusMix = 200,
    OpenFMAddressChorusRate,
    OpenFMAddressChorusDepth,
    OpenFMAddressDelayMix,
    OpenFMAddressDelayTime,
    OpenFMAddressDelayFeedback,
    OpenFMAddressReverbMix,
    OpenFMAddressReverbSize,
    OpenFMAddressReverbDamp,
    OpenFMAddressVolume,
    OpenFMAddressBendRange,
    OpenFMAddressEffectEnd,
};

/// The OpenFM instrument. Used in-process by the standalone app and as the
/// AUv3 extension's audio unit; both share the same C++ engine.
///
/// Every method declared here is safe to call from any thread unless noted.
NS_SWIFT_SENDABLE
@interface OpenFMAudioUnit : AUAudioUnit

@property (class, nonatomic, readonly) AudioComponentDescription openFMDescription;

/// Routing flags from the engine's algorithm table. `slot` 0 is OP6.
+ (NSInteger)algorithmFlags:(NSInteger)algorithm slot:(NSInteger)slot;
/// A 156-byte initialised voice.
+ (NSData *)initialPatchData;

/// Display name of the current patch. Not limited to the 10 DX7 characters.
@property (atomic, copy) NSString *patchName;
/// Called on the main queue after a host restores state through `fullState`.
@property (atomic, copy, nullable) void (^stateRestoredHandler)(void);

/// The current voice as 156 unpacked DX7 bytes (byte 155 = operator mask).
- (NSData *)patchData;
- (void)loadPatchData:(NSData *)data;

- (float)valueForAddress:(AUParameterAddress)address;
/// Writes straight to the engine, bypassing the parameter tree.
- (void)setValue:(float)value forAddress:(AUParameterAddress)address;

/// On-screen keyboard events. Call from one thread only (the main thread).
- (void)noteOn:(uint8_t)note velocity:(uint8_t)velocity NS_SWIFT_NAME(noteOn(_:velocity:));
- (void)noteOff:(uint8_t)note NS_SWIFT_NAME(noteOff(_:));
- (void)sendController:(uint8_t)controller value:(uint8_t)value;
/// External MIDI received outside the render cycle. Call from one thread only.
- (void)receiveMIDIStatus:(uint8_t)status data1:(uint8_t)data1 data2:(uint8_t)data2;
- (void)panic;

/// Copies the latest `count` output samples for the oscilloscope.
- (void)copyScopeInto:(float *)buffer count:(NSInteger)count;
@property (nonatomic, readonly) NSInteger activeVoices;

@end

NS_ASSUME_NONNULL_END
