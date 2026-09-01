# iOS live Try-On capture — person images are taken in the app

> iOS/iPadOS only. Android is untouched by every line of this document.

## 1. The rule

On iPhone and iPad, the person image a garment is rendered onto can only come
from a capture taken inside the app, in this app's own camera session. The
device Photo Library, Files, the clipboard, a URL, a share extension and the
system `image_picker` camera sheet are all closed to it.

The Photo Library is **not** disabled app-wide, and must not be: Closet garment
uploads, profile pictures, community posts and giveaway listings all still use
it, and that is what `NSPhotoLibraryUsageDescription` exists for.

## 2. Two lenses, one session

| | Front (default) | Rear |
|---|---|---|
| Who holds the device | nobody — it is propped up | a person helping |
| Preview | mirrored | **not** mirrored |
| Shutter | auto, after stable framing | a manual button |
| Countdown | 3-2-1, with sound, haptic and a full-screen pulse | none |
| 10-second timer | yes | no |
| Full-body guide + framing feedback | yes | yes |

Front is the default **every time the screen opens**. Switching is a per-session
choice: it never persists into a new capture flow.

The switch control is built only when the device actually reports both lenses.
They are enumerated at open, never assumed — an iPad without a rear camera and a
simulator both exist, and a control that throws when pressed is worse than no
control.

## 3. Why the rear lens exists

A full-body photo of yourself, alone, at arm's length, is not possible. The
front-lens flow solves that by having the user prop the device up and step back
— but that needs a surface, space, and enough light at three metres. When
somebody else is available to hold the phone, the rear lens is simply the better
camera and the better framing, and refusing it pushed people toward the one
thing this feature exists to prevent: picking an old photo out of Photos.

Adding it changes nothing about **where** a person image may come from. Both
lenses are the same in-app session.

## 4. Naming

The policy value is `MediaSourceRule.liveCameraOnly` (it was
`liveFrontCameraOnly`). The rule was never about the lens; naming it after one
made the rear lens look like a weakening of the gate when it is not. The
service-level denial in `AvatarService.pick` is unchanged and still refuses
**every** `ImageSource` — gallery and system camera alike — before any
permission prompt, picker, file copy, upload, AI job or credit.

## 5. Controller lifecycle

Switching is ordered, and each step earns its place:

1. cancel the fallback timer and reset the auto-capture tracker — a countdown
   that survived the switch would fire the shutter on a lens the user did not
   choose;
2. detach the camera from the field, then `stopFrames()`, then `dispose()` —
   detaching first means a lifecycle teardown racing the switch cannot find the
   same object and dispose it twice;
3. open the new lens;
4. re-check `mounted` and the phase — if the app was backgrounded mid-switch the
   newly opened session is disposed rather than kept;
5. only then restart frame analysis.

A second tap is refused while a switch, an open or a capture is in flight, so a
rapid double tap cannot leave an orphaned controller.

## 6. Permissions

`NSCameraUsageDescription` covers both lenses and the Closet garment camera.
**No `NSMicrophoneUsageDescription`** — the session opens with
`enableAudio: false` on both lenses, and the countdown uses system sounds,
haptics and an on-screen pulse. Nothing in this flow requests Photo Library
access.

## 7. App Review notes (draft)

> **Try-On person photos**
>
> On iPhone and iPad, the person image used for Try-On can only be captured
> live inside the app. The front camera is the default for solo capture, and
> the user may switch to the rear camera when someone is helping take their
> full-body photo. Device Photos cannot be selected as the Try-On person image.
>
> Photo Library access remains in the app for other features — adding garments
> to the user's private closet, profile pictures, community posts and giveaway
> listings — but it cannot be used as the Try-On person image.

## 8. Tests

`app/test/ui/ios_live_capture_test.dart` covers the capture screen (both
lenses, the switch lifecycle, mirroring, shutter de-duplication, retake and
layout); `app/test/ui/ios_tryon_person_image_test.dart` covers the policy at
every entry point; `app/test/guest/ios_live_capture_denial_test.dart` proves a
guest reaches neither lens — not even a lens enumeration;
`app/test/core/media/media_source_policy_test.dart` pins the platform matrix.
