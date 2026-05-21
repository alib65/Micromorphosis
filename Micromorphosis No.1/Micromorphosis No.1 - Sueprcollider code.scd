// ------------------------------------------------------------
// DYNAMIC EDO 3D BINAURAL HEADPHONE ECOSYSTEM
// Live MIDI Control Edition - FIXED GAIN & PLUCK TRIGGERS
// ------------------------------------------------------------
//
// --- CONCEPTUAL DESCRIPTION ---
// This piece is a live-controlled, generative ambient soundscape
// designed specifically for headphone listening. It creates an
// immersive, spatialized "ecosystem" comprising three distinct
// sonic elements: a crackling, low-frequency fire, a generative
// Karplus-Strong harp, and a synthetic, formant-based vocal choir.
//
// At the heart of the composition is a breathing, microtonal
// harmonic structure. The tuning system fluidly morphs between
// a pure, halved Equal Division of the Octave (EDO) scale and a
// full, complex EDO scale. As time progresses, the harmonic
// language constantly shifts in and out of focus, dictated by a
// dynamic LFO. The entire ecosystem is highly reactive, waiting
// for a performer to shape its tension, timbre, and scale in
// real-time via MIDI control.
//
// --- TECHNICAL ARCHITECTURE ---
//
// 1. SPATIALIZATION & ROUTING
// All synths output to a 4-channel Ambisonic audio bus (~ambiBus).
// A dedicated tail synth (\binauralDecoder) folds this down to
// stereo using crossfeed delays, low-pass filtering, and spatial
// cues to mimic human hearing, finishing with a FreeVerb2 reverb.
//
// 2. SYNTHESIS ENGINE
// - \humanSinger: Saw/pulse waves with vibrato, routed through
//   four narrow BPFs (formants). A *25 multiplier recovers the
//   heavy gain reduction caused by the narrow filters.
// - \harpGesture: A Karplus-Strong physical model. Impulse.ar(0)
//   guarantees a clean strike, and a hardcoded max delay time (0.2)
//   prevents NaN (Not a Number) buffer silences.
// - \fireEcosystem: Blends high-passed Dust (crackle) and low-passed
//   BrownNoise (roar), balanced to avoid masking the tonal elements.
//
// 3. HARMONIC ENGINE & "THE MORPH"
// Frequencies are dynamically calculated based on a user-defined
// EDO (~currentEDO). The ~globalMorph variable acts as a sine LFO,
// smoothly interpolating notes between integer scale steps (pure)
// and fractional scale steps (full).
//
// 4. GENERATIVE ROUTINE (~player)
// Uses 'fork' to run three independent, infinitely looping threads:
// - Harp Logic: Randomly builds arpeggiated chords or single plucks.
// - Vocal Logic: Manages 3 voices firing on probability coin tosses.
// - Monitor: Tracks the morph state and posts clean scale updates.
//
// 5. MIDI MAPPINGS
// CC 12 / 13    : Current EDO (7-28) & Morph LFO Duration (1-10s)
// CC 2,3,14,15  : Fire Amp, Tension, HPF, LPF
// CC 4,5,16,17  : Harp Vol, Chaos, LPF, HPF
// CC 6,8,18,19  : Singer Vol, Chaos, LPF, HPF
// ------------------------------------------------------------

// Link to Video: https://www.youtube.com/watch?v=winPBkp4y0w

// Copyright (c) 2026 Ali Balighi.

(
// ------------------------------------------------------------
// DYNAMIC EDO 3D BINAURAL HEADPHONE ECOSYSTEM
// Live MIDI Control Edition - FIXED GAIN & PLUCK TRIGGERS
// ------------------------------------------------------------

s.waitForBoot({

    // 1. GLOBAL SETTINGS & MIDI INIT
    ~netAddr = NetAddr("127.0.0.1", 12345);
    ~masterAmp = 0.6; // Boosted overall Master volume slightly
    ~baseFreq = 65.41;
    ~ambiBus = Bus.audio(s, 4);

    // Initialize Global Variables (Safe Defaults)
    ~globalMorph = 0.5;
    ~harpVol = 1.0; ~harpLPF = 20000; ~harpHPF = 20; ~harpChaos = 0.5;
    ~singerVol = 1.0; ~singerLPF = 10000; ~singerHPF = 20; ~singerChaos = 0.5;

    // NEW: Variables for EDO scale and Modulation Duration
    ~currentEDO = 14;
    ~modDuration = 5; // Default to 5 (maps to your original 0.03 speed)

    // Start MIDI
    MIDIClient.init;
    MIDIIn.connectAll;

    // UPDATED: Calculates frequency dynamically based on ~currentEDO
    ~calcFreq = { |step, baseFreq, morph|
        var stepHalf = step.round(2);
        var currentStep = stepHalf.blend(step, morph);
        baseFreq * (2 ** (currentStep / ~currentEDO));
    };

    // 2. SYNTH DEFINITIONS

    // A. BINAURAL DECODER
    SynthDef(\binauralDecoder, { |in, out=0, mix=0.4|
        var w, x, y, z, left, right, leftCross, rightCross, zCue;
        #w, x, y, z = In.ar(in, 4);

        left = (w * 0.707) + (y * 0.5) + (x * 0.5);
        right = (w * 0.707) - (y * 0.5) + (x * 0.5);

        leftCross = DelayC.ar(LPF.ar(right, 1200), 0.001, 0.0006) * 0.35;
        rightCross = DelayC.ar(LPF.ar(left, 1200), 0.001, 0.0006) * 0.35;

        left = left + leftCross;
        right = right + rightCross;

        zCue = HPF.ar(z, 5000) * 0.4;

        // Output with reverb and spatial cues
        Out.ar(out, FreeVerb2.ar(left + zCue, right + zCue, mix, 0.9, 0.2) * ~masterAmp);
    }).add;

    // B. HUMAN SINGER (Massively boosted BPF compensation)
    SynthDef(\humanSinger, { |out=0, freq=440, amp=0.2, gate=1, azi=0, ele=0, lpf=10000, hpf=20|
        var source, formants, env, sig, vib, jitter;

        vib = SinOsc.kr(LFDNoise1.kr(0.2).range(4.8, 5.4), 0, freq * 0.01);
        jitter = LFDNoise3.ar(10).range(0.997, 1.003);
        source = Saw.ar((freq + vib) * jitter, 0.2) + Pulse.ar((freq + vib) * jitter, 0.5, 0.2);

        formants = [
            BPF.ar(source, 800, 0.1), BPF.ar(source, 1150, 0.15),
            BPF.ar(source, 2900, 0.2), BPF.ar(source, 3900, 0.2)
        ];

        // FIXED: Multiplied by 25 to recover volume lost in the narrow Band Pass Filters
        sig = Mix.ar(formants) * 25;

        sig = HPF.ar(LPF.ar(sig, lpf.clip(500, 20000)), hpf.clip(20, 1000));
        sig = FreeVerb.ar(sig, 0.7, 0.95);
        env = EnvGen.kr(Env.asr(2, 1, 4), gate, doneAction: 2);

        Out.ar(out, PanB.ar(sig * env * amp, azi, ele, 1));
    }).add;

    // C. EXPRESSIVE HARP (Fixed Pluck trigger and max delay time)
    SynthDef(\harpGesture, { |out=0, freq=440, amp=0.3, duration=1.0,
                             aziStart=0, aziEnd=0, eleStart=0, eleEnd=0, coef=0.4, lpf=20000, hpf=20|
        var sig, env, noise, delayTime, azi, ele;

        noise = WhiteNoise.ar(0.8);
        delayTime = freq.reciprocal;

        // FIXED: Impulse.ar(0) ensures a perfect strike. '0.2' gives it plenty of memory buffer to prevent NaN silence.
        sig = Pluck.ar(noise, Impulse.ar(0), 0.2, delayTime, duration, coef);

        sig = HPF.ar(LPF.ar(sig, lpf.clip(500, 20000)), hpf.clip(20, 1000));
        env = EnvGen.kr(Env.perc(0.01, duration, curve: -4), doneAction: 2);

        azi = Line.kr(aziStart, aziEnd, duration);
        ele = Line.kr(eleStart, eleEnd, duration);
        Out.ar(out, PanB.ar(sig * env * amp, azi, ele, 1));
    }).add;

    // D. FIRE (Adjusted baseline volume so it doesn't overpower the rest)
    SynthDef(\fireEcosystem, { |out=0, gate=1, amp=0.1, tension=0.5, lpf=15000, hpf=20|
        var crackle, roar, sig, env, azi, ele;

        crackle = HPF.ar(Dust.ar(4 + (tension * 20)), 2500) * (1 + tension * 2);
        roar = LPF.ar(BrownNoise.ar(0.04), 400 + (tension * 1000));

        sig = crackle + roar;
        sig = HPF.ar(LPF.ar(sig, lpf.clip(500, 20000)), hpf.clip(20, 1000));

        env = EnvGen.kr(Env.asr(5, 1, 5), gate, doneAction: 2);
        azi = LFNoise1.kr(0.1).range(-1, 1);
        ele = LFNoise1.kr(0.1).range(-1, 1);
        Out.ar(out, PanB.ar(sig * env * amp, azi, ele, 1));
    }).add;

    s.sync;

    // Route audio and start global fire synth
    ~fxSynth = Synth.tail(s, \binauralDecoder, [\in, ~ambiBus]);
    ~fireSynth = Synth(\fireEcosystem, [\out, ~ambiBus]);

    // ------------------------------------------------------------
    // 3. MIDI CC MAPPINGS
    // ------------------------------------------------------------

    // --- NEW: DYNAMIC SCALE & MODULATION ---
    MIDIFunc.cc({ |val|
        ~currentEDO = val.linlin(0, 127, 7, 28).round(1).asInteger;
        (~currentEDO.asString ++ "-EDO").postln;
    }, 12, 0);

    MIDIFunc.cc({ |val|
        ~modDuration = val.linlin(0, 127, 1, 10).round(1);
        ("duration of morphing: " ++ ~modDuration.asString ++ " seconds").postln;
    }, 13, 0);

    // --- NOISE (Fire) ---
    MIDIFunc.cc({ |val|
        var ampVal = val.linlin(0, 127, 0.0, 0.3);
        ~fireSynth.set(\amp, ampVal);
        ~netAddr.sendMsg("/vaziri/data", ~globalMorph, val.linlin(0, 127, 0.0, 1.0), 0, ampVal * 3);
    }, 2, 0);
    MIDIFunc.cc({ |val| ~fireSynth.set(\hpf, val.linexp(0, 127, 20, 2000)); }, 14, 0);
    MIDIFunc.cc({ |val| ~fireSynth.set(\lpf, val.linexp(0, 127, 800, 20000)); }, 15, 0);
    MIDIFunc.cc({ |val| ~fireSynth.set(\tension, val.linlin(0, 127, 0.0, 1.0)); }, 3, 0);

    // --- HARP ---
    MIDIFunc.cc({ |val| ~harpVol = val.linlin(0, 127, 0.0, 2.0); }, 4, 0);
    MIDIFunc.cc({ |val| ~harpLPF = val.linexp(0, 127, 800, 20000); }, 16, 0);
    MIDIFunc.cc({ |val| ~harpHPF = val.linexp(0, 127, 20, 2000); }, 17, 0);
    MIDIFunc.cc({ |val| ~harpChaos = val.linlin(0, 127, 0.0, 1.0); }, 5, 0);

    // --- SINGERS ---
    MIDIFunc.cc({ |val| ~singerVol = val.linlin(0, 127, 0.0, 2.0); }, 6, 0);
    MIDIFunc.cc({ |val| ~singerLPF = val.linexp(0, 127, 2500, 20000); }, 18, 0);
    MIDIFunc.cc({ |val| ~singerHPF = val.linexp(0, 127, 20, 1000); }, 19, 0);
    MIDIFunc.cc({ |val| ~singerChaos = val.linlin(0, 127, 0.0, 1.0); }, 8, 0);


    // 4. PERFORMANCE ROUTINE
    ~player = Routine({
        var globalTime = 0;

        // --- HARP LOGIC ---
        fork {
            var step = 14;
            loop {
                var isChord = (~harpChaos + 0.1).coin;
                var dur = [0.2, 0.5, 2.0, 4.0].wchoose([0.3, 0.3, 0.2, 0.2]);
                var rootFreq = ~calcFreq.(step, ~baseFreq * 2, ~globalMorph);

                var aziStart = rrand(-1.0, 1.0); var aziEnd = rrand(-1.0, 1.0);
                var eleStart = rrand(-1.0, 1.0); var eleEnd = rrand(-1.0, 1.0);
                var coefVal = rrand(0.2, 0.6);

                if(isChord) {
                    var numNotes = rrand(3, 5);
                    var chordOffsets = [0, 2, 4, 6, 8, 10, 14].scramble.keep(numNotes);
                    fork {
                        chordOffsets.do { |offset|
                            var noteFreq = ~calcFreq.(step + offset, ~baseFreq * 2, ~globalMorph);
                            var ampLevel = 0.25 * ~harpVol;
                            Synth(\harpGesture, [
                                \out, ~ambiBus, \freq, noteFreq,
                                \amp, ampLevel, \lpf, ~harpLPF, \hpf, ~harpHPF,
                                \duration, dur * rrand(0.8, 1.2),
                                \aziStart, aziStart, \aziEnd, aziEnd,
                                \eleStart, eleStart, \eleEnd, eleEnd, \coef, coefVal
                            ]);
                            ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~harpChaos, aziStart, ampLevel);
                            (rrand(0.03, 0.09) * (1.1 - ~harpChaos)).wait;
                        };
                    };
                } {
                    var ampLevel = 0.4 * ~harpVol;
                    Synth(\harpGesture, [
                        \out, ~ambiBus, \freq, rootFreq,
                        \amp, ampLevel, \lpf, ~harpLPF, \hpf, ~harpHPF,
                        \duration, dur,
                        \aziStart, aziStart, \aziEnd, aziEnd,
                        \eleStart, eleStart, \eleEnd, eleEnd, \coef, coefVal
                    ]);
                    ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~harpChaos, aziStart, ampLevel);
                };

                // Wraps the steps dynamically based on the current EDO
                step = (step + [2, 4, 7, -3].choose) % ~currentEDO;
                (dur * rrand(0.3, 0.8) * (1.2 - ~harpChaos)).max(0.15).wait;
            }
        };

        // --- VOCAL TRIO LOGIC ---
        [ [4, -0.8], [2, 0.8], [1, 0.0] ].do { |params, i|
            fork {
                var octave = params[0], fixedAzi = params[1];
                var step = i * 4;
                loop {
                    if((~singerChaos + 0.2).coin) {
                        var voiceAzi = fixedAzi;
                        var voiceEle = rrand(-0.5, 0.5);
                        var freq = ~calcFreq.(step, ~baseFreq * octave, ~globalMorph);
                        var ampLevel = 0.15 * ~singerVol;

                        var voice = Synth(\humanSinger, [
                            \out, ~ambiBus, \freq, freq, \azi, voiceAzi, \ele, voiceEle,
                            \amp, ampLevel, \lpf, ~singerLPF, \hpf, ~singerHPF
                        ]);

                        ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~singerChaos, voiceAzi, ampLevel);
                        rrand(3.0, 6.0).wait;
                        voice.set(\gate, 0);
                    };
                    // Wraps the steps dynamically based on the current EDO
                    step = (step + [1, 2, -1].choose) % ~currentEDO;
                    (rrand(3.0, 8.0) * (1.2 - ~singerChaos)).max(1.0).wait;
                }
            }
        };

        // --- MONITOR ---
        loop {
            var morphPct;

            // UPDATED: Dynamic LFO Speed based on ~modDuration mapped from CC 13
            // A modDuration of 5 equals the original 0.03 speed.
            ~globalMorph = ((globalTime * (0.15 / ~modDuration)).sin * 0.5) + 0.5;

            morphPct = (~globalMorph * 100).round(0.1);
            if(globalTime % 5 == 0) {
                if(~globalMorph < 0.05) {
                    (">>> SCALE: PURE " ++ (~currentEDO/2).asInteger ++ "-EDO").postln;
                } {
                    if(~globalMorph > 0.95) {
                        (">>> SCALE: FULL " ++ ~currentEDO ++ "-EDO").postln;
                    } {
                        ("--- Morphing:" + morphPct + "% | Bridge Active ---").postln;
                    };
                };
            };

            1.0.wait;
            globalTime = globalTime + 1;
        }
    });

    "3D Binaural System Updated! Cleaned up CC monitor prints.".postln;
});
)

~player.play;
