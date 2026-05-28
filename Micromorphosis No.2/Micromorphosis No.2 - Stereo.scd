(
// ------------------------------------------------------------
// DYNAMIC EDO 3D BINAURAL HEADPHONE ECOSYSTEM
// Live MIDI Control Edition - DYNAMIC INSTRUMENT RANGES
// ------------------------------------------------------------

s.waitForBoot({

    // 1. GLOBAL SETTINGS & MIDI INIT
    ~netAddr = NetAddr("127.0.0.1", 12345);
    ~masterAmp = 0.6;
    ~ambiBus = Bus.audio(s, 4);
    ~delayBus = Bus.audio(s, 1);

    // Initialize Global Variables
    ~globalMorph = 0.5;

    // --- NEW: Dynamic Base Frequencies for each instrument ---
    ~timpaniBase = 32.7;   // Defaults to C1
    ~trumpetBase = 261.63; // Defaults to C4
    ~bellBase = 1046.5;    // Defaults to C6

    // Trumpet Globals
    ~trumpetVol = 0.0;
    ~trumpetLPF = 15000;
    ~trumpetHPF = 50; // CC 17 removed, resting at default
    ~trumpetChaos = 0.5;
    ~trumpetModIndex = 10;

    // Timpani Globals
    ~timpaniVol = 0.0;
    ~timpaniLPF = 15000; // CC 15 removed, resting at default
    ~timpaniHPF = 20;
    ~timpaniMallet = 0.8;

    // Bell Globals
    ~bellVol = 0.0;
    ~bellLPF = 15000;
    ~bellHPF = 500; // CC 19 removed, resting at default
    ~bellChaos = 0.5;
    ~bellDecay = 5.0;

    ~currentEDO = 12;
    ~modDuration = 5;

    // Start MIDI
    MIDIClient.init;
    MIDIIn.connectAll;

    // Calculates frequency dynamically
    ~calcFreq = { |step, baseFreq, morph|
        var stepHalf = step.round(2);
        var currentStep = stepHalf.blend(step, morph);
        baseFreq * (2 ** (currentStep / ~currentEDO));
    };

    // 2. SYNTH DEFINITIONS (Unchanged)

    SynthDef(\binauralDecoder, { |in, out=0, mix=0.4|
        var w, x, y, z, left, right, leftCross, rightCross, zCue, finalOutput;
        #w, x, y, z = In.ar(in, 4);

        left = (w * 0.707) + (y * 0.5) + (x * 0.5);
        right = (w * 0.707) - (y * 0.5) + (x * 0.5);

        leftCross = DelayC.ar(LPF.ar(right, 1200), 0.001, 0.0006) * 0.35;
        rightCross = DelayC.ar(LPF.ar(left, 1200), 0.001, 0.0006) * 0.35;

        left = left + leftCross;
        right = right + rightCross;

        zCue = HPF.ar(z, 5000) * 0.4;

        finalOutput = FreeVerb2.ar(left + zCue, right + zCue, mix, 0.9, 0.2) * ~masterAmp;

        Out.ar(out, Limiter.ar(finalOutput, -1.dbamp, 0.01));
    }).add;

    SynthDef(\spatialScatteredDelay, {
        arg in, out, delayTime=0.4, feedback=0.6, mix=0.8;
        var sig = In.ar(in, 1);
        var local = LocalIn.ar(1) + sig;
        var taps, fbSig;

        taps = Array.fill(4, { |i|
            var tapTime = delayTime * (i + 1);
            var tapSig = DelayC.ar(local, 4.0, tapTime);

            var azi = Lag.kr(LFNoise0.kr(1 / tapTime).range(-pi, pi), 0.1);
            var ele = Lag.kr(LFNoise0.kr(1 / tapTime).range(-pi/2, pi/2), 0.1);
            var dist = Lag.kr(LFNoise0.kr(1 / tapTime).range(2.0, 12.0), 0.1);

            var distAmp = 1 / (dist ** 1.5);
            var distLPF = (15000 / dist).clip(500, 20000);

            tapSig = LPF.ar(tapSig, distLPF) * distAmp;
            PanB.ar(tapSig, azi, ele, 1);
        });

        fbSig = DelayC.ar(local, 4.0, delayTime * 4);
        LocalOut.ar(fbSig * feedback);
        Out.ar(out, Mix(taps) * mix);
    }).add;

    SynthDef(\fmTrumpet, {
        arg out = 0, delayOut = 0, delaySend = 0.0, freq = 440, amp = 0.1, gate = 1,
            azi = 0, ele = 0, rotSpeed = 0.0,
            modIndex = 10, vibRate = 6, vibDepth = 0.02, vibDelay = 0.4,
            lpf = 15000, hpf = 50;

        var ampEnv, modEnv, vib, carrier, modulator, index, sig, movingAzi, cleanSig;

        vib = SinOsc.kr(vibRate) * vibDepth * EnvGen.kr(Env([0, 0, 1], [vibDelay, 0.5]));
        modEnv = EnvGen.kr(Env.adsr(0.05, 0.2, 0.6, 0.2), gate);
        index = modIndex * modEnv;

        modulator = SinOsc.ar(freq * (4 + vib)) * freq * index;
        carrier = SinOsc.ar(freq * (2 + vib) + modulator);

        ampEnv = EnvGen.kr(Env.adsr(0.08, 0.1, 0.8, 0.3), gate, doneAction: 2);

        sig = LPF.ar(carrier, lpf.clip(500, 20000));
        sig = HPF.ar(sig, hpf.clip(20, 1000));

        cleanSig = sig * ampEnv * amp;
        movingAzi = azi + (SinOsc.kr(rotSpeed) * pi);

        Out.ar(out, PanB.ar(cleanSig, movingAzi, ele, 1));
        Out.ar(delayOut, cleanSig * delaySend);
    }).add;

    SynthDef(\ambiTimpani_heavy, {
        arg out=0, delayOut=0, delaySend=0.0, freq=90, amp=0.8, azi=0, ele=0, time=3.0, mallet=0.8, lpf=15000, hpf=20;
        var pitchDrop, body, strike, membrane, sig, env, cleanSig;

        pitchDrop = EnvGen.ar(Env([freq * 1.4, freq], [0.06], \exp));
        body = SinOsc.ar(pitchDrop) * EnvGen.ar(Env.perc(0.01, time, 1, -3));

        membrane = PMOsc.ar(
            carfreq: freq * 1.5,
            modfreq: freq * 0.47,
            pmindex: EnvGen.ar(Env.perc(0.01, 0.5)) * 4
        ) * 0.3 * EnvGen.ar(Env.perc(0.01, time * 0.6));

        strike = BPF.ar(WhiteNoise.ar, 500 + (mallet * 500), 0.5) * EnvGen.ar(Env.perc(0.001, 0.04)) * mallet;

        sig = body + membrane + strike;
        sig = (sig * 1.5).tanh * 0.8;

        sig = LPF.ar(sig, lpf.clip(500, 20000));
        sig = HPF.ar(sig, hpf.clip(20, 1000));

        env = EnvGen.kr(Env.perc(0.005, time), doneAction: 2);
        cleanSig = sig * env * amp;

        Out.ar(out, PanB.ar(cleanSig, azi, ele, 1));
        Out.ar(delayOut, cleanSig * delaySend);
    }).add;

    SynthDef(\ambiBell, {
        arg out=0, delayOut=0, delaySend=0.0, freq=440, amp=0.5, azi=0, ele=0, decay=5.0, distance=1.0, lpf=15000, hpf=500;
        var sig, env, exciter, freqs, amps, decs, distAmp, distLPF, cleanSig;

        freqs = freq * [0.5, 1, 1.19, 1.56, 2, 2.51, 2.66, 3.01, 4.1];
        amps = [0.25, 1, 0.8, 0.5, 0.9, 0.4, 0.3, 0.2, 0.1];
        decs = [1, 1, 0.8, 0.5, 0.7, 0.4, 0.3, 0.2, 0.1] * decay;

        exciter = EnvGen.ar(Env.perc(0.001, 0.05)) * WhiteNoise.ar(0.1);
        exciter = exciter + (EnvGen.ar(Env.perc(0.001, 0.01)) * SinOsc.ar(freq * 2));

        sig = DynKlank.ar(`[freqs, amps, decs], exciter) * 0.5;

        distAmp = amp / (distance ** 1.5);
        distLPF = (lpf / distance).clip(1000, 20000);

        sig = LPF.ar(sig, distLPF);
        sig = HPF.ar(sig, hpf.clip(20, 1000));

        env = EnvGen.kr(Env.perc(0.001, decay), doneAction: 2);
        cleanSig = sig * env * distAmp;

        Out.ar(out, PanB.ar(cleanSig, azi, ele, 1));
        Out.ar(delayOut, cleanSig * delaySend);
    }).add;

    s.sync;

    ~delaySynth = Synth.tail(s, \spatialScatteredDelay, [\in, ~delayBus, \out, ~ambiBus, \delayTime, 0.55]);
    ~fxSynth = Synth.after(~delaySynth, \binauralDecoder, [\in, ~ambiBus]);

    // ------------------------------------------------------------
    // 3. MIDI CC MAPPINGS
    // ------------------------------------------------------------

    MIDIFunc.cc({ |val|
        var edoOptions = [6, 12, 24, 48];
        var index = val.linlin(0, 127, 0, 3).round(1).asInteger;
        if(~currentEDO != edoOptions[index]) {
            ~currentEDO = edoOptions[index];
            (">>> SWAPPED SCALE TO: " ++ ~currentEDO.asString ++ "-EDO").postln;
        };
    }, 12, 0);

    MIDIFunc.cc({ |val| ~modDuration = val.linlin(0, 127, 1, 10).round(1); }, 13, 0);

    // --- TIMPANI CCs ---
    MIDIFunc.cc({ |val| ~timpaniVol = val.linlin(0, 127, 0.0, 1.5); }, 2, 0);
    MIDIFunc.cc({ |val| ~timpaniHPF = val.linexp(0, 127, 20, 2000); }, 14, 0);
    // NEW: CC 15 maps Timpani Range (C1 to G6)
    MIDIFunc.cc({ |val| ~timpaniBase = val.linexp(0, 127, 32.7, 1568.0); }, 15, 0);
    MIDIFunc.cc({ |val| ~timpaniMallet = val.linlin(0, 127, 0.1, 1.0); }, 3, 0);

    // --- TRUMPET CCs ---
    MIDIFunc.cc({ |val| ~trumpetVol = val.linlin(0, 127, 0.0, 2.0); }, 4, 0);
    MIDIFunc.cc({ |val| ~trumpetLPF = val.linexp(0, 127, 800, 20000); }, 16, 0);
    // NEW: CC 17 maps Trumpet Range (C1 to G6)
    MIDIFunc.cc({ |val| ~trumpetBase = val.linexp(0, 127, 32.7, 1568.0); }, 17, 0);
    MIDIFunc.cc({ |val| ~trumpetChaos = val.linlin(0, 127, 0.0, 1.0); }, 5, 0);
    MIDIFunc.cc({ |val| ~trumpetModIndex = val.linlin(0, 127, 2.0, 20.0); }, 6, 0);

    // --- BELL CCs ---
    MIDIFunc.cc({ |val| ~bellVol = val.linlin(0, 127, 0.0, 2.0); }, 6, 0);
    MIDIFunc.cc({ |val| ~bellChaos = val.linlin(0, 127, 0.0, 1.0); }, 8, 0);
    MIDIFunc.cc({ |val| ~bellDecay = val.linlin(0, 127, 1.0, 10.0); }, 9, 0);
    MIDIFunc.cc({ |val| ~bellLPF = val.linexp(0, 127, 2000, 20000); }, 18, 0);
    // NEW: CC 19 maps Bell Range (C1 to G6)
    MIDIFunc.cc({ |val| ~bellBase = val.linexp(0, 127, 32.7, 1568.0); }, 19, 0);

    // 4. PERFORMANCE ROUTINE
    ~player = Routine({
        var globalTime = 0;

        // --- LAYER 1: RHYTHMIC / CHORDAL BRASS ---
        fork {
            var step = 14;
            loop {
                var isChord = (~trumpetChaos + 0.1).coin;
                var dur = [0.2, 0.5, 1.0, 2.0].wchoose([0.4, 0.3, 0.2, 0.1]);

                // Uses dynamic ~trumpetBase
                var rootFreq = ~calcFreq.(step, ~trumpetBase, ~globalMorph);

                var aziStart = rrand(-pi, pi);
                var eleStart = rrand(-pi/2, pi/2);

                if(isChord) {
                    var numNotes = rrand(3, 5);
                    var chordOffsets = [0, 2, 4, 6, 8, 10, 14].scramble.keep(numNotes);
                    fork {
                        chordOffsets.do { |offset|
                            var noteFreq = ~calcFreq.(step + offset, ~trumpetBase, ~globalMorph);
                            var ampLevel = 0.25 * ~trumpetVol;
                            var synth = Synth(\fmTrumpet, [
                                \out, ~ambiBus, \delayOut, ~delayBus, \delaySend, 0.4,
                                \freq, noteFreq, \amp, ampLevel, \lpf, ~trumpetLPF, \hpf, ~trumpetHPF,
                                \azi, aziStart, \ele, eleStart, \modIndex, ~trumpetModIndex,
                                \rotSpeed, ~trumpetChaos * 1.5
                            ]);
                            ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~trumpetChaos, aziStart, ampLevel);

                            fork { (dur * rrand(0.8, 1.2)).wait; synth.set(\gate, 0); };
                            (rrand(0.03, 0.09) * (1.1 - ~trumpetChaos)).wait;
                        };
                    };
                } {
                    var ampLevel = 0.4 * ~trumpetVol;
                    var synth = Synth(\fmTrumpet, [
                        \out, ~ambiBus, \delayOut, ~delayBus, \delaySend, 0.4,
                        \freq, rootFreq, \amp, ampLevel, \lpf, ~trumpetLPF, \hpf, ~trumpetHPF,
                        \azi, aziStart, \ele, eleStart, \modIndex, ~trumpetModIndex,
                        \rotSpeed, ~trumpetChaos * 1.5
                    ]);
                    ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~trumpetChaos, aziStart, ampLevel);
                    fork { dur.wait; synth.set(\gate, 0); };
                };

                step = (step + [2, 4, 7, -3].choose) % ~currentEDO;
                (dur * rrand(0.3, 0.8) * (1.2 - ~trumpetChaos)).max(0.15).wait;
            }
        };

        // --- LAYER 2: SUSTAINED BRASS LINES ---
        [ [4, -0.8], [2, 0.8], [1, 0.0] ].do { |params, i|
            fork {
                var octave = params[0];
                var fixedAzi = params[1] * pi;
                var step = i * 4;
                loop {
                    if((~trumpetChaos + 0.2).coin) {
                        var voiceAzi = fixedAzi;
                        var voiceEle = rrand(-pi/4, pi/4);

                        // Uses dynamic ~trumpetBase (scaled by octave spread)
                        var freq = ~calcFreq.(step, ~trumpetBase * octave, ~globalMorph);
                        var ampLevel = 0.15 * ~trumpetVol;

                        var voice = Synth(\fmTrumpet, [
                            \out, ~ambiBus, \delayOut, ~delayBus, \delaySend, 0.3,
                            \freq, freq, \azi, voiceAzi, \ele, voiceEle,
                            \amp, ampLevel, \lpf, ~trumpetLPF, \hpf, ~trumpetHPF,
                            \modIndex, ~trumpetModIndex * 0.7, \rotSpeed, rrand(0.05, 0.2)
                        ]);

                        ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~trumpetChaos, voiceAzi, ampLevel);

                        rrand(3.0, 6.0).wait;
                        voice.set(\gate, 0);
                    };

                    step = (step + [1, 2, -1].choose) % ~currentEDO;
                    (rrand(3.0, 8.0) * (1.2 - ~trumpetChaos)).max(1.0).wait;
                }
            }
        };

        // --- LAYER 3: HEAVY TIMPANI ANCHOR ---
        fork {
            var step = 0;
            loop {
                var dur = rrand(4.0, 8.0);

                // Uses dynamic ~timpaniBase
                var rootFreq = ~calcFreq.(step, ~timpaniBase, ~globalMorph);
                var azi = rrand(-pi/3, pi/3);
                var ampLevel = 0.9 * ~timpaniVol;

                Synth(\ambiTimpani_heavy, [
                    \out, ~ambiBus, \delayOut, ~delayBus, \delaySend, 0.15,
                    \freq, rootFreq, \amp, ampLevel, \azi, azi, \ele, -pi/3,
                    \time, dur * 0.7, \mallet, ~timpaniMallet,
                    \lpf, ~timpaniLPF, \hpf, ~timpaniHPF
                ]);

                ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~timpaniMallet, azi, ampLevel);

                step = (step + [0, 7].choose) % ~currentEDO;
                (dur * rrand(0.9, 1.2)).wait;
            }
        };

        // --- LAYER 4: ETHEREAL BELLS WITH DEPTH ---
        fork {
            var step = 7;
            loop {
                var dur = rrand(2.0, 5.0);
                var isCluster = (~bellChaos + 0.1).coin;

                var aziStart = rrand(-pi, pi);
                var eleStart = rrand(0.1, pi/2);

                if(isCluster) {
                    var numNotes = rrand(2, 4);
                    var offsets = [0, 2, 4, 7, 9].scramble.keep(numNotes);
                    fork {
                        offsets.do { |offset|
                            // Uses dynamic ~bellBase
                            var noteFreq = ~calcFreq.(step + offset, ~bellBase, ~globalMorph);
                            var ampLevel = 0.25 * ~bellVol;
                            var bellDistance = rrand(1.0, 8.0);

                            Synth(\ambiBell, [
                                \out, ~ambiBus, \delayOut, ~delayBus, \delaySend, 0.6,
                                \freq, noteFreq, \amp, ampLevel, \decay, ~bellDecay * rrand(0.8, 1.2),
                                \azi, aziStart, \ele, eleStart, \distance, bellDistance,
                                \lpf, ~bellLPF, \hpf, ~bellHPF
                            ]);

                            ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~bellChaos, aziStart, ampLevel);

                            (rrand(0.1, 0.35) * (1.1 - ~bellChaos)).max(0.05).wait;
                        }
                    }
                } {
                    // Uses dynamic ~bellBase
                    var noteFreq = ~calcFreq.(step, ~bellBase, ~globalMorph);
                    var ampLevel = 0.4 * ~bellVol;
                    var bellDistance = rrand(1.0, 6.0);

                    Synth(\ambiBell, [
                        \out, ~ambiBus, \delayOut, ~delayBus, \delaySend, 0.6,
                        \freq, noteFreq, \amp, ampLevel, \decay, ~bellDecay,
                        \azi, aziStart, \ele, eleStart, \distance, bellDistance,
                        \lpf, ~bellLPF, \hpf, ~bellHPF
                    ]);

                    ~netAddr.sendMsg("/vaziri/data", ~globalMorph, ~bellChaos, aziStart, ampLevel);
                };

                step = (step + [1, 2, 4, 5, -2].choose) % ~currentEDO;
                (dur * rrand(0.6, 1.5) * (1.2 - ~bellChaos)).max(0.2).wait;
            }
        };

        // --- MONITOR ---
        loop {
            var morphPct = (~globalMorph * 100).round(0.1);
            ~globalMorph = ((globalTime * (0.15 / ~modDuration)).sin * 0.5) + 0.5;

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

    "3D Binaural System Updated! Dynamic Ranges mapped to CC 15, 17, 19.".postln;
});
)

~player.play;