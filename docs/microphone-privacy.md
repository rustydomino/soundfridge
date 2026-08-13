# Microphone Privacy Behavior

SoundFridge itself does not use microphone input and does not create a
virtual microphone device. Its virtual proxy devices contain output streams
only.

## Observed macOS behavior

Some physical audio devices, such as the Focusrite Scarlett Solo, are duplex
devices containing both input and output channels.

When SoundBridgeHost starts audio I/O on the Scarlett for playback, macOS
CoreAudio performs a microphone privacy authorization request even though
SoundFridge does not consume the device's input streams.

This appears to be normal CoreAudio/TCC behavior associated with starting I/O
on a duplex physical audio device rather than an accidental microphone access
request by SoundFridge.

## Tests

Tested on macOS Sequoia with a Scarlett Solo USB.

- CoreAudio device enumeration produces a microphone privacy preflight but did
  not by itself produce a real microphone-access request.
- Direct AudioDevice IOProc registration on the Scarlett produced a real
  microphone request.
- The same IOProc experiment on output-only Mac mini Speakers did not produce
  a real microphone request.
- The same experiment on an output-only HDMI device did not produce a real
  microphone request.
- An explicitly output-only Audio Queue could be created and bound to the
  Scarlett without a real microphone request.
- Starting that Audio Queue caused a real microphone request.
- The normal SoundFridge Host also causes the request when starting playback
  through the Scarlett.

## Denying microphone permission

Choosing "Don't Allow" does not prevent SoundFridge from operating normally.

Verified behavior after denying microphone permission:

- SoundFridge proxy device is created.
- Audio plays through the Scarlett.
- macOS master-volume control continues to work.
- The Scarlett remains available as an input device to other applications.
- Microphone privacy permission remains per-application; denying SoundFridge
  does not deny microphone access to a DAW or recording application.

Therefore SoundFridge does not require microphone permission for its intended
operation.

## UX implications

Onboarding should explain this before macOS displays its microphone prompt.

Users of duplex audio interfaces should be told that:

- macOS may request microphone access because the physical interface contains
  input channels.
- SoundFridge does not record audio or create a microphone device.
- The user can choose "Don't Allow."
- Denying SoundFridge does not disable the interface's recording inputs for
  other applications.

## Signing / update behavior

During development, rebuilding SoundBridgeHost changed its code identity
enough that TCC did not match an existing microphone decision and prompted
again.

Before release, test a properly signed production Host to confirm that a
previous "Don't Allow" decision survives:

1. Host restart.
2. Physical-device disconnect/reconnect.
3. Installation of another duplex device.
4. SoundFridge application update.