# Synthetic two-speaker session

`two-speaker-session.m4a` is a fully synthetic, fictional conversation. It contains no patient data and is used only with deterministic fake transcription and diarization outputs. The fixture is mono AAC at 22,050 Hz, runs for 12.531 seconds, and is about 100 KB.

## Script and voices

The lines alternate between two clearly different synthetic voices:

1. Samantha: “I felt more settled after I took a walk yesterday.”
2. Daniel: “What helped you notice that change?”
3. Samantha: “I slowed down and paid attention to my breathing.”
4. Daniel: “Try writing down one moment like that before we meet again.”

The canonical macOS source commands are:

```sh
say -v Samantha -r 175 -o 01.aiff "I felt more settled after I took a walk yesterday."
say -v Daniel -r 175 -o 02.aiff "What helped you notice that change?"
say -v Samantha -r 175 -o 03.aiff "I slowed down and paid attention to my breathing."
say -v Daniel -r 175 -o 04.aiff "Try writing down one moment like that before we meet again."
```

The checked-in artifact was built in a restricted macOS command runner where `say` listed Samantha and Daniel but emitted zero audio frames because their system voice assets were unavailable. The equivalent offline voices `en-us+f3` and `en-gb+m3` produced the four source WAV files for this build:

```sh
espeak -v en-us+f3 -s 175 -w 01.wav "I felt more settled after I took a walk yesterday."
espeak -v en-gb+m3 -s 175 -w 02.wav "What helped you notice that change?"
espeak -v en-us+f3 -s 175 -w 03.wav "I slowed down and paid attention to my breathing."
espeak -v en-gb+m3 -s 175 -w 04.wav "Try writing down one moment like that before we meet again."
```

A temporary Swift utility used `AVAudioFile` to concatenate the four files in order with 300 milliseconds of silence after each line. It required identical mono 22,050 Hz PCM inputs and rejected empty or oversized sources. The utility and individual line files were deleted after export. The final compact fixture was encoded with:

```sh
ffmpeg -i two-speaker-session.caf -c:a aac -b:a 64k two-speaker-session.m4a
afinfo two-speaker-session.m4a
```

Tests do not perform live recognition or diarization. They pass this playable file URL to `FakeTranscriber` and `FakeDiarizer`, then verify the timestamp alignment policy.
