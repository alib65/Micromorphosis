(
s.waitForBoot({
	 var scriptDir = thisProcess.nowExecutingPath.dirname;

    // ==========================================
    // 0. SETUP THE PYTHON BRIDGE & VARIABLES
    // ==========================================
    ~pythonBridge = NetAddr("127.0.0.1", 12345);

    // Store our visuals state globally so they can be sent alongside the continuous volume
    ~visualTension = 0.0;
    ~visualMotion = 0.0;
    ~visualMode = 0.0;

    // Listen for the continuous volume from the master synth and send it to Python!
    OSCdef(\volTracker, { |msg|
        var realVolume = msg[3];
        // We multiply the volume by 3.5 to make sure the visuals pop on screen
        ~pythonBridge.sendMsg('/vaziri/data', ~visualTension, ~visualMotion, ~visualMode, realVolume * 3.5);
    }, '/liveAmp');
    // ==========================================
    // 1. LOAD 20 WAV SAMPLES (01.wav to 20.wav)
    // ==========================================

    if(scriptDir.isNil) {
        "WARNING: Script is not saved! Please save the file first so SC knows where to find the WAVs.".warn;
    };

    ~buffers = (1..20).collect { |i|
        var filename = i.asString.padLeft(2, "0") ++ ".wav";
        var filepath = scriptDir +/+ filename;

        Buffer.readChannel(s, filepath, channels: [0]);
    };

    s.sync;

    // ==========================================
    // 2. SYNTH DEFS (AMBISONICS & DECODER)
    // ==========================================

    ~ambiBus = Bus.audio(s, 3);

    // Sampler Synth using 2D Ambisonics (UPDATED WITH 5 RANDOM FX MODES)
    SynthDef(\ambiSampler, {
        |out=0, bufnum=0, rate=1, amp=0.5, dur=3.0, speed=1, distance=1,
         fxMode=0, distortAmt=0.1, delayTime=0.05, delayFeedback=1.5|

        var sig, env, azimuth, startPhase, spinDir;
        var isReverse, actualRate, startPos;
        var sig0, sig1, sig2, sig3;

        // Envelope scaled to duration
        env = EnvGen.kr(Env([0, 1, 1, 0], [0.1, 0.8, 0.1], \sine), timeScale: dur, doneAction: 2);

        // --- EFFECT 5: REVERSE SOUND ---
        // If fxMode == 4, reverse playback by flipping the rate and starting at the end of the buffer
        isReverse = fxMode > 3.5;
        actualRate = rate * Select.kr(isReverse, [1, -1]);
        startPos = Select.kr(isReverse, [0, BufFrames.kr(bufnum) - 2]);

        // Read the guaranteed 1-channel buffer
        sig = PlayBuf.ar(1, bufnum, actualRate * BufRateScale.kr(bufnum), startPos: startPos, loop: 0);

        // --- EFFECT MULTIPLEXER ---

        // 1. Natural (Normal or Reversed depending on PlayBuf)
        sig0 = sig;

        // 2. Multiple to Noise
        sig1 = sig * WhiteNoise.ar(1);

        // 3. Distortion (10% to 40% mapped via distortAmt 0.1 to 0.4)
        // Drives the gain heavily into a hard clip, then lowers the output to match
        sig2 = (sig * (1 + (distortAmt * 15))).clip2(1.0) * (1 - (distortAmt * 0.5));

        // 4. Harsh Delay (Short comb filter / slapback style)
        sig3 = sig + CombN.ar(sig, 0.2, delayTime, delayFeedback);

        // Route the signal based on the fxMode argument (0=Nat, 1=Noise, 2=Dist, 3=Delay, 4=Rev)
        sig = Select.ar(fxMode, [sig0, sig1, sig2, sig3, sig0]);

        // Distance Simulation (Softened the volume drop slightly using .sqrt)
        sig = LPF.ar(sig, 18000 / distance.max(1));
        sig = sig * env * amp * (1 / distance.sqrt);

        // --- SPATIAL BALANCE FIX ---
        startPhase = Rand(0.0, 2.0);
        spinDir = Select.kr(IRand(0, 1), [-1, 1]);

        azimuth = LFSaw.kr(speed * spinDir, startPhase);

        // Encode into 2D B-format (W, X, Y)
        Out.ar(out, PanB2.ar(sig, azimuth, 1));
    }).add;

// Standard Stereo Decoder for listening
    SynthDef(\ambiDecoder, { |in=0, out=0, masterVolume=4.0|
        var wxy = In.ar(in, 3);
        var decoded = DecodeB2.ar(2, wxy[0], wxy[1], wxy[2]);
        var ampVal; // Variable to hold our volume measurement

        // --- VOLUME BOOST & SAFETY LIMITER ---
        decoded = Limiter.ar(decoded * masterVolume, 0.95, 0.01);

        // ==========================================
        // THE FIX: LIVE AMPLITUDE TRACKING
        // ==========================================
        // Measure the amplitude of the mixed down stereo signal
        ampVal = Amplitude.kr(Mix.new(decoded));

        // Send the volume value back to the language 30 times a second using the '/liveAmp' tag
        SendReply.kr(Impulse.kr(30), '/liveAmp', ampVal);

        Out.ar(out, decoded);
    }).add;

    // Start the decoder.
    ~decoderNode = Synth.tail(s, \ambiDecoder, [\in, ~ambiBus, \out, 0, \masterVolume, 4.0]);

    // ==========================================
    // 3. MASTER SEQUENCER
    // ==========================================

    ~edoRoutine = Routine({
        var baseScales = [13, 21, 34, 55, 89];
        var isRandomCycle = false;
        var modPhaseDuration = 5.0;

        var getNextSequence = {
            var seq = if(isRandomCycle) {
                baseScales.copy.scramble;
            } {
                baseScales.copy;
            };
            isRandomCycle = isRandomCycle.not;
            seq;
        };

        var currentSeq = getNextSequence.value;
        var nextSeq = getNextSequence.value;
        var idx = 0;

        0.5.wait;

        loop {
            var currentEdo = currentSeq[idx];
            var nextEdo;
            var elapsed = 0;
            var modEdo;

            if(idx == (currentSeq.size - 1)) {
                nextEdo = nextSeq[0];
            } {
                nextEdo = currentSeq[idx + 1];
            };

            modEdo = (currentEdo + nextEdo) / 2;

            // --- PHASE 1: STABLE ---
            "\n=== STABLE PHASE: %-EDO (Duration: %s) ===".format(currentEdo, currentEdo).postln;

            elapsed = 0;
            while ( { elapsed < currentEdo } ) {
                var dur = rrand(2.0, 4.0);
                var waitTime = rrand(0.2, 0.6);

                var degree = rrand(0, currentEdo * 5);
                var rate = 2 ** (degree / currentEdo);

                var dist = currentEdo.linexp(13, 89, 1.0, 6.0);
                var spd = currentEdo.linexp(13, 89, 0.1, 3.0);
                var dyn = rrand(0.3, 1.0);

                // --- RANDOM EFFECT GENERATION ---
                var randFx = [0, 1, 2, 3, 4].choose; // 0=Nat, 1=Noise, 2=Dist, 3=Delay, 4=Rev
                var randDistAmt = rrand(0.1, 0.4);   // 10% to 40%
                var randDlyTime = rrand(0.01, 0.08); // Short harsh metallic delay
                var randDlyFbk = rrand(1.0, 3.0);    // Delay feedback time

                Synth(\ambiSampler, [
                    \out, ~ambiBus,
                    \bufnum, ~buffers.choose.bufnum,
                    \rate, rate,
                    \amp, dyn,
                    \dur, dur,
                    \distance, dist,
                    \speed, spd,
                    \fxMode, randFx,
                    \distortAmt, randDistAmt,
                    \delayTime, randDlyTime,
                    \delayFeedback, randDlyFbk
                ]);

                waitTime.wait;
                elapsed = elapsed + waitTime;
            };

            // --- PHASE 2: MODULATION ---
            "\n>>> MODULATING: %-EDO passing to %-EDO (Current Grid: %-EDO) <<<"
                .format(currentEdo, nextEdo, modEdo).postln;

            elapsed = 0;
            while ( { elapsed < modPhaseDuration } ) {
                var dur = rrand(1.5, 3.0);
                var waitTime = rrand(0.15, 0.4);

                var degree = rrand(0, (modEdo * 5).asInteger);
                var rate = 2 ** (degree / modEdo);

                var dist = modEdo.linexp(13, 89, 1.0, 6.0);
                var spd = modEdo.linexp(13, 89, 0.1, 3.0);
                var dyn = rrand(0.2, 0.8);

                // --- RANDOM EFFECT GENERATION ---
                var randFx = [0, 1, 2, 3, 4].choose;
                var randDistAmt = rrand(0.1, 0.4);
                var randDlyTime = rrand(0.01, 0.08);
                var randDlyFbk = rrand(1.0, 3.0);

                Synth(\ambiSampler, [
                    \out, ~ambiBus,
                    \bufnum, ~buffers.choose.bufnum,
                    \rate, rate,
                    \amp, dyn,
                    \dur, dur,
                    \distance, dist,
                    \speed, spd,
                    \fxMode, randFx,
                    \distortAmt, randDistAmt,
                    \delayTime, randDlyTime,
                    \delayFeedback, randDlyFbk
                ]);

                waitTime.wait;
                elapsed = elapsed + waitTime;
            };

            // --- CYCLE MANAGEMENT ---
            idx = idx + 1;
            if(idx >= currentSeq.size) {
                currentSeq = nextSeq;
                nextSeq = getNextSequence.value;
                idx = 0;

                "\n=========================================".postln;
                "NEW CYCLE STARTING".postln;
                if(isRandomCycle.not) { "Mode: RANDOMIZED (No Repetition)".postln } { "Mode: EXACT ORDER".postln };
                "=========================================\n".postln;
            };
        };
    }).play;
});
)

/*
// ==========================================
// TO STOP THE PIECE AND FREE RESOURCES:
// ==========================================
~edoRoutine.stop;
~decoderNode.free;
~buffers.do(_.free);
s.freeAll;
*/