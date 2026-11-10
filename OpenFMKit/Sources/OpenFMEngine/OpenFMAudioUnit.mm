// Copyright 2026 The OpenFM Authors
// SPDX-License-Identifier: Apache-2.0

#import "OpenFMAudioUnit.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMIDI/CoreMIDI.h>

#include <algorithm>
#include <memory>
#include <vector>

#include "Engine.h"
#include "fm_core.h"

using openfm::Engine;

namespace {

NSString *const kStatePatch = @"openfm.patch";
NSString *const kStateName = @"openfm.name";
NSString *const kStateFx = @"openfm.fx";

struct OpParam { const char *ident; const char *name; int max; };
const OpParam kOpParams[21] = {
    {"eg_rate1", "EG Rate 1", 99}, {"eg_rate2", "EG Rate 2", 99},
    {"eg_rate3", "EG Rate 3", 99}, {"eg_rate4", "EG Rate 4", 99},
    {"eg_level1", "EG Level 1", 99}, {"eg_level2", "EG Level 2", 99},
    {"eg_level3", "EG Level 3", 99}, {"eg_level4", "EG Level 4", 99},
    {"breakpoint", "Break Point", 99}, {"left_depth", "Left Depth", 99},
    {"right_depth", "Right Depth", 99}, {"left_curve", "Left Curve", 3},
    {"right_curve", "Right Curve", 3}, {"rate_scaling", "Rate Scaling", 7},
    {"amp_mod_sens", "Amp Mod Sensitivity", 3}, {"velocity_sens", "Velocity Sensitivity", 7},
    {"level", "Output Level", 99}, {"mode", "Fixed Frequency", 1},
    {"coarse", "Frequency Coarse", 31}, {"fine", "Frequency Fine", 99},
    {"detune", "Detune", 14},
};

struct GlobalParam { int address; const char *ident; const char *name; int max; };
const GlobalParam kGlobalParams[] = {
    {126, "peg_rate1", "Pitch EG Rate 1", 99}, {127, "peg_rate2", "Pitch EG Rate 2", 99},
    {128, "peg_rate3", "Pitch EG Rate 3", 99}, {129, "peg_rate4", "Pitch EG Rate 4", 99},
    {130, "peg_level1", "Pitch EG Level 1", 99}, {131, "peg_level2", "Pitch EG Level 2", 99},
    {132, "peg_level3", "Pitch EG Level 3", 99}, {133, "peg_level4", "Pitch EG Level 4", 99},
    {134, "algorithm", "Algorithm", 31}, {135, "feedback", "Feedback", 7},
    {136, "key_sync", "Oscillator Key Sync", 1}, {137, "lfo_speed", "LFO Speed", 99},
    {138, "lfo_delay", "LFO Delay", 99}, {139, "lfo_pitch_depth", "LFO Pitch Depth", 99},
    {140, "lfo_amp_depth", "LFO Amp Depth", 99}, {141, "lfo_sync", "LFO Key Sync", 1},
    {142, "lfo_wave", "LFO Wave", 5}, {143, "pitch_mod_sens", "Pitch Mod Sensitivity", 7},
    {144, "transpose", "Transpose", 48},
};

struct FxParam { const char *ident; const char *name; float min; float max; AudioUnitParameterUnit unit; };
const FxParam kFxParams[Engine::kFxCount] = {
    {"chorus_mix", "Chorus Mix", 0, 1, kAudioUnitParameterUnit_Generic},
    {"chorus_rate", "Chorus Rate", 0.05f, 8, kAudioUnitParameterUnit_Hertz},
    {"chorus_depth", "Chorus Depth", 0, 1, kAudioUnitParameterUnit_Generic},
    {"delay_mix", "Delay Mix", 0, 1, kAudioUnitParameterUnit_Generic},
    {"delay_time", "Delay Time", 0.02f, 1.5f, kAudioUnitParameterUnit_Seconds},
    {"delay_feedback", "Delay Feedback", 0, 0.95f, kAudioUnitParameterUnit_Generic},
    {"reverb_mix", "Reverb Mix", 0, 1, kAudioUnitParameterUnit_Generic},
    {"reverb_size", "Reverb Size", 0, 1, kAudioUnitParameterUnit_Generic},
    {"reverb_damp", "Reverb Damping", 0, 1, kAudioUnitParameterUnit_Generic},
    {"volume", "Volume", 0, 1, kAudioUnitParameterUnit_Generic},
    {"bend_range", "Pitch Bend Range", 0, 12, kAudioUnitParameterUnit_MIDINoteNumber},
};

// Realtime-safe: only touches atomics.
inline void applyParameter(Engine *engine, AUParameterAddress address, float value) {
    if (address < 145) {
        engine->setParam((int)address, (int)lroundf(value));
    } else if (address >= OpenFMAddressOperatorEnable && address < OpenFMAddressOperatorEnable + 6) {
        // Operator n (1-based) lives in engine slot 6 - n.
        const int slot = 5 - (int)(address - OpenFMAddressOperatorEnable);
        int mask = engine->param(155);
        mask = value >= 0.5f ? (mask | (1 << slot)) : (mask & ~(1 << slot));
        engine->setParam(155, mask);
    } else if (address >= OpenFMAddressChorusMix && address < OpenFMAddressEffectEnd) {
        const int id = (int)(address - OpenFMAddressChorusMix);
        engine->setFx(id, std::clamp(value, kFxParams[id].min, kFxParams[id].max));
    }
}

inline float readParameter(const Engine *engine, AUParameterAddress address) {
    if (address < 145) return (float)engine->param((int)address);
    if (address >= OpenFMAddressOperatorEnable && address < OpenFMAddressOperatorEnable + 6) {
        const int slot = 5 - (int)(address - OpenFMAddressOperatorEnable);
        return (engine->param(155) >> slot) & 1 ? 1.0f : 0.0f;
    }
    if (address >= OpenFMAddressChorusMix && address < OpenFMAddressEffectEnd) {
        return engine->fx((int)(address - OpenFMAddressChorusMix));
    }
    return 0;
}

// Translates one Universal MIDI Packet into a MIDI 1.0 channel message.
inline void handleUMP(Engine *engine, const UInt32 *words, int count) {
    int i = 0;
    while (i < count) {
        const UInt32 w = words[i];
        const int type = (int)(w >> 28);
        if (type == 2) {
            engine->handleMidi((w >> 16) & 0xff, (w >> 8) & 0x7f, w & 0x7f);
            i += 1;
        } else if (type == 4 && i + 1 < count) {
            const UInt32 d = words[i + 1];
            const uint8_t status = (w >> 16) & 0xff;
            const uint8_t index = (w >> 8) & 0x7f;
            switch (status & 0xf0) {
                case 0x90: engine->handleMidi(status, index, std::max<uint8_t>(1, (uint8_t)(d >> 25))); break;
                case 0x80: engine->handleMidi(status, index, 0); break;
                case 0xb0: engine->handleMidi(status, index, (uint8_t)(d >> 25)); break;
                case 0xe0: {
                    const UInt32 bend14 = d >> 18;
                    engine->handleMidi(status, bend14 & 0x7f, (bend14 >> 7) & 0x7f);
                    break;
                }
                default: break;
            }
            i += 2;
        } else {
            static const int sizes[16] = {1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4};
            i += sizes[type];
        }
    }
}

// Buffers the render block falls back to when the host supplies none.
// The block holds a pointer to this struct, never to the buffers themselves:
// a host may ask for the render block before render resources are allocated,
// so anything captured by value at that moment would be empty for ever.
struct RenderState {
    std::vector<float> scratch[2];
};

}  // namespace

@implementation OpenFMAudioUnit {
    std::unique_ptr<Engine> _engine;
    std::unique_ptr<RenderState> _render;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_outputBusArray;
    AUParameterTree *_tree;
}

@synthesize patchName = _patchName;
@synthesize stateRestoredHandler = _stateRestoredHandler;

+ (AudioComponentDescription)openFMDescription {
    AudioComponentDescription desc = {};
    desc.componentType = kAudioUnitType_MusicDevice;
    desc.componentSubType = 'Opfm';
    desc.componentManufacturer = 'OpFM';
    return desc;
}

+ (NSInteger)algorithmFlags:(NSInteger)algorithm slot:(NSInteger)slot {
    return FmCore::flags((int)algorithm, (int)slot);
}

+ (NSData *)initialPatchData {
    uint8_t patch[Engine::kPatchSize];
    Engine::initPatch(patch);
    return [NSData dataWithBytes:patch length:sizeof(patch)];
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (!self) return nil;

    _engine = std::make_unique<Engine>();
    _render = std::make_unique<RenderState>();
    _patchName = @"Init Voice";

    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:outError];
    if (!_outputBus) return nil;
    _outputBus.maximumChannelCount = 2;
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                             busType:AUAudioUnitBusTypeOutput
                                                              busses:@[_outputBus]];
    [self buildParameterTree];
    self.maximumFramesToRender = 4096;
    return self;
}

- (void)buildParameterTree {
    const AudioUnitParameterOptions flags =
        kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
    NSMutableArray<AUParameterNode *> *groups = [NSMutableArray array];

    for (int op = 1; op <= 6; op++) {
        NSMutableArray<AUParameterNode *> *children = [NSMutableArray array];
        const int base = (6 - op) * 21;
        for (int i = 0; i < 21; i++) {
            const OpParam &p = kOpParams[i];
            [children addObject:[AUParameterTree
                createParameterWithIdentifier:@(p.ident)
                                         name:[NSString stringWithFormat:@"OP%d %s", op, p.name]
                                      address:(AUParameterAddress)(base + i)
                                          min:0
                                          max:p.max
                                         unit:p.max == 1 ? kAudioUnitParameterUnit_Boolean : kAudioUnitParameterUnit_Indexed
                                     unitName:nil
                                        flags:flags
                                 valueStrings:nil
                          dependentParameters:nil]];
        }
        [children addObject:[AUParameterTree
            createParameterWithIdentifier:@"enabled"
                                     name:[NSString stringWithFormat:@"OP%d On", op]
                                  address:OpenFMAddressOperatorEnable + (AUParameterAddress)(op - 1)
                                      min:0
                                      max:1
                                     unit:kAudioUnitParameterUnit_Boolean
                                 unitName:nil
                                    flags:flags
                             valueStrings:nil
                      dependentParameters:nil]];
        [groups addObject:[AUParameterTree createGroupWithIdentifier:[NSString stringWithFormat:@"op%d", op]
                                                                name:[NSString stringWithFormat:@"Operator %d", op]
                                                            children:children]];
    }

    NSMutableArray<AUParameterNode *> *voice = [NSMutableArray array];
    for (const GlobalParam &p : kGlobalParams) {
        [voice addObject:[AUParameterTree
            createParameterWithIdentifier:@(p.ident)
                                     name:@(p.name)
                                  address:(AUParameterAddress)p.address
                                      min:0
                                      max:p.max
                                     unit:p.max == 1 ? kAudioUnitParameterUnit_Boolean : kAudioUnitParameterUnit_Indexed
                                 unitName:nil
                                    flags:flags
                             valueStrings:nil
                      dependentParameters:nil]];
    }
    [groups addObject:[AUParameterTree createGroupWithIdentifier:@"voice" name:@"Voice" children:voice]];

    NSMutableArray<AUParameterNode *> *fx = [NSMutableArray array];
    for (int i = 0; i < Engine::kFxCount; i++) {
        const FxParam &p = kFxParams[i];
        [fx addObject:[AUParameterTree
            createParameterWithIdentifier:@(p.ident)
                                     name:@(p.name)
                                  address:OpenFMAddressChorusMix + (AUParameterAddress)i
                                      min:p.min
                                      max:p.max
                                     unit:p.unit
                                 unitName:nil
                                    flags:flags
                             valueStrings:nil
                      dependentParameters:nil]];
    }
    [groups addObject:[AUParameterTree createGroupWithIdentifier:@"effects" name:@"Effects" children:fx]];

    _tree = [AUParameterTree createTreeWithChildren:groups];

    // The blocks capture the engine, never self, so they are safe on the
    // render thread and do not create a retain cycle.
    Engine *engine = _engine.get();
    _tree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        applyParameter(engine, param.address, value);
    };
    _tree.implementorValueProvider = ^AUValue(AUParameter *param) {
        return readParameter(engine, param.address);
    };
}

#pragma mark - AUAudioUnit

- (AUParameterTree *)parameterTree { return _tree; }
- (AUAudioUnitBusArray *)outputBusses { return _outputBusArray; }
- (BOOL)canProcessInPlace { return NO; }
- (NSArray<NSNumber *> *)channelCapabilities { return @[@0, @2]; }
- (MIDIProtocolID)AudioUnitMIDIProtocol { return kMIDIProtocol_1_0; }

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) return NO;
    _engine->prepare(_outputBus.format.sampleRate);
    _render->scratch[0].assign(self.maximumFramesToRender, 0.0f);
    _render->scratch[1].assign(self.maximumFramesToRender, 0.0f);
    return YES;
}

- (void)deallocateRenderResources {
    [super deallocateRenderResources];
}

- (AUInternalRenderBlock)internalRenderBlock {
    Engine *engine = _engine.get();
    RenderState *state = _render.get();

    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp *timestamp,
                              AUAudioFrameCount frameCount,
                              NSInteger outputBusNumber,
                              AudioBufferList *outputData,
                              const AURenderEvent *realtimeEventListHead,
                              AURenderPullInputBlock __unsafe_unretained pullInputBlock) {
        // Read at render time: these are sized in allocateRenderResources.
        float *scratchL = state->scratch[0].data();
        float *scratchR = state->scratch[1].data();
        if (frameCount > state->scratch[0].size()) return kAudioUnitErr_TooManyFramesToProcess;

        const UInt32 byteSize = frameCount * sizeof(float);
        const bool stereo = outputData->mNumberBuffers > 1;
        if (outputData->mBuffers[0].mData == nullptr) outputData->mBuffers[0].mData = scratchL;
        if (stereo && outputData->mBuffers[1].mData == nullptr) outputData->mBuffers[1].mData = scratchR;
        float *left = (float *)outputData->mBuffers[0].mData;
        float *right = stereo ? (float *)outputData->mBuffers[1].mData : scratchR;
        for (UInt32 i = 0; i < outputData->mNumberBuffers; i++) {
            outputData->mBuffers[i].mDataByteSize = byteSize;
        }

        const AUEventSampleTime start = (AUEventSampleTime)timestamp->mSampleTime;
        const AURenderEvent *event = realtimeEventListHead;
        AUAudioFrameCount done = 0;
        while (true) {
            // Apply every event due at this point in the buffer.
            while (event != nullptr && event->head.eventSampleTime <= start + (AUEventSampleTime)done) {
                switch (event->head.eventType) {
                    case AURenderEventParameter:
                    case AURenderEventParameterRamp:
                        applyParameter(engine, event->parameter.parameterAddress, event->parameter.value);
                        break;
                    case AURenderEventMIDI:
                        if (event->MIDI.length >= 1) {
                            engine->handleMidi(event->MIDI.data[0],
                                               event->MIDI.length > 1 ? event->MIDI.data[1] : 0,
                                               event->MIDI.length > 2 ? event->MIDI.data[2] : 0);
                        }
                        break;
                    case AURenderEventMIDIEventList: {
                        const MIDIEventList *list = &event->MIDIEventsList.eventList;
                        const MIDIEventPacket *packet = &list->packet[0];
                        for (UInt32 i = 0; i < list->numPackets; i++) {
                            handleUMP(engine, packet->words, (int)packet->wordCount);
                            packet = MIDIEventPacketNext(packet);
                        }
                        break;
                    }
                    default:
                        break;
                }
                event = event->head.next;
            }
            if (done >= frameCount) break;
            AUAudioFrameCount until = frameCount;
            if (event != nullptr) {
                const AUEventSampleTime offset = event->head.eventSampleTime - start;
                until = (AUAudioFrameCount)std::clamp<AUEventSampleTime>(offset, done + 1, frameCount);
            }
            engine->render(left + done, right + done, (int)(until - done));
            done = until;
        }

        if (!stereo) {
            for (AUAudioFrameCount i = 0; i < frameCount; i++) left[i] = 0.5f * (left[i] + right[i]);
        }
        return noErr;
    };
}

#pragma mark - State

- (NSDictionary<NSString *, id> *)fullState {
    NSMutableDictionary *state = [[super fullState] mutableCopy] ?: [NSMutableDictionary dictionary];
    state[kStatePatch] = [self patchData];
    state[kStateName] = self.patchName ?: @"";
    NSMutableArray *fx = [NSMutableArray arrayWithCapacity:Engine::kFxCount];
    for (int i = 0; i < Engine::kFxCount; i++) [fx addObject:@(_engine->fx(i))];
    state[kStateFx] = fx;
    return state;
}

- (void)setFullState:(NSDictionary<NSString *, id> *)fullState {
    [super setFullState:fullState];
    NSData *patch = fullState[kStatePatch];
    if ([patch isKindOfClass:NSData.class]) [self loadPatchData:patch];
    NSString *name = fullState[kStateName];
    if ([name isKindOfClass:NSString.class]) self.patchName = name;
    NSArray *fx = fullState[kStateFx];
    if ([fx isKindOfClass:NSArray.class]) {
        for (NSUInteger i = 0; i < fx.count && i < Engine::kFxCount; i++) {
            if ([fx[i] isKindOfClass:NSNumber.class]) {
                applyParameter(_engine.get(), OpenFMAddressChorusMix + i, [fx[i] floatValue]);
            }
        }
    }
    void (^handler)(void) = self.stateRestoredHandler;
    if (handler) dispatch_async(dispatch_get_main_queue(), handler);
}

- (NSData *)patchData {
    uint8_t patch[Engine::kPatchSize];
    _engine->copyPatch(patch);
    return [NSData dataWithBytes:patch length:sizeof(patch)];
}

- (void)loadPatchData:(NSData *)data {
    if (data.length < Engine::kPatchSize) return;
    _engine->loadPatch((const uint8_t *)data.bytes);
}

- (float)valueForAddress:(AUParameterAddress)address {
    return readParameter(_engine.get(), address);
}

- (void)setValue:(float)value forAddress:(AUParameterAddress)address {
    applyParameter(_engine.get(), address, value);
}

#pragma mark - Performance

- (void)noteOn:(uint8_t)note velocity:(uint8_t)velocity {
    _engine->pushEvent(Engine::kQueueUI, 0x90, note & 0x7f, std::max<uint8_t>(1, velocity & 0x7f));
}

- (void)noteOff:(uint8_t)note {
    _engine->pushEvent(Engine::kQueueUI, 0x80, note & 0x7f, 0);
}

- (void)sendController:(uint8_t)controller value:(uint8_t)value {
    _engine->pushEvent(Engine::kQueueUI, 0xb0, controller & 0x7f, value & 0x7f);
}

- (void)receiveMIDIStatus:(uint8_t)status data1:(uint8_t)data1 data2:(uint8_t)data2 {
    _engine->pushEvent(Engine::kQueueMIDI, status, data1, data2);
}

- (void)panic { _engine->panic(); }

- (void)copyScopeInto:(float *)buffer count:(NSInteger)count {
    _engine->copyScope(buffer, (int)count);
}

- (NSInteger)activeVoices { return _engine->activeVoices(); }

@end
