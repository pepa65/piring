# piring v2
_Branch 'ubuntu1804'_
**Control a school sound system from a Raspberry Pi with touchscreen**
Using Ubuntu 18.04 and software that is no longer well supported beyond 2022

## Usage
`ring`

## Hardware and pinout
Raspberry Pi with 3.5" 480x320 touchscreen and a relay that controls the
power to the amplifier, and a audio lead from the pi's output to the
amplifier's input, so that apart from ringing the various school bells,
alarms can be sounded and announcements can be made. The relay is powered from
the 5V pin(2) closest to the corner and ground by the pin (39) closest to the
opposite corner. The signal pin (37) is next to the ground pin.

## Function
The Normal schedule will ring on every weekday, unless that day is
marked as a No-Bells day. Special schedules will always ring on any day
they are scheduled, but then the Normal schedule will be cancelled, unless
at least 1 of the Special schedules is an Additional schedule (having a `+`
after the date in file $ringdates). The (optional) file $ringdates lists
the dates for the Special & Additional schedules and for the No-Bells days
(Saturdays & Sundays are No-Bells days by default).
The time schedules are defined in the file $ringtimes.
The touchscreen can be used to turn on the amplifier to make an
announcement or play (alarm) sound files.
- The input files $ringdates and $ringtimes are read from the same directory
  as where the $ring script resides, the $buttons script is in subdirectory
  $touchscreen together with all images that are part of it,
  and all the sound files reside in subdirectory $soundfiles.
- The input files $ringtimes and $ringdates are read and checked for
  proper syntax & semantics.
- The ringtone sound files referenced in $ringtimes are symlinks `R.ring`
  in where `R` is the digit referenced (`0` is the default ringtone);
  when referenced they need to be present in $soundfiles.
- The optional (alarm)button sound files are symlinks `B.alarm` (B:1..4)
  which are played when the corresponding touchscreen buttons are selected.
- The temporary file $state also resides in $touchscreen and it is used to
  pass the touchscreen state that is generated by the python script $buttons
  (which is started from the $ring script).
- When all is in order the program starts and output is logged to stdout.

## Format inputfiles
- All lines starting with `#` as the first character are skipped as comments.
- $ringtimes: lines with `HH:MMsR` where `s` is Schedule (Normal schedule is
  space/empty, and Special schedule codes have an alphabetic character) and
  `R` is the numerical single digit Ringtone code. If `R` is space/empty it
  references the default ringtone file `0.ring`. If `R` is `-` it means that
  time slot is muted regardless of any other schedules. In general, the `R`
  (numeric) refers to the ringtone file `R.ring`.
  All characters after position 7 are ignored as a comment.
- $ringdates (optional): lines of `YYYY-MM-DDsP` or `YYYY-MM-DD/YYYY-MM-DDsP`
  where `s` is either space/empty (for No-Bells dates) or the alphabetical
  Special schedule code. The `P` can be empty/space (replace the Normal
  schedule) or `+` (in addition to the Normal schedule). The double date format
  is the beginning and end of an inclusive date range.
  There can be multiple Special schedules for the same date, and all get rung
  (even if that date is also a No-Bells date!).
  All characters after position 12 resp. 23 are ignored as a comment.

## Required
wiringpi(gpio) coreutils(sleep fold readlink) sox(play) date
[$buttons: python2.7 python-pygame] [`rc.local`: tmux(optional)]

## Deployment
See file `INSTALL`

## License
GPLv3+  https://spdx.org/licenses/GPL-3.0-or-later.html


# splay
**Play sound files over the amplifier**

## Usage
`splay [<file> ...]`
    if no <file> is given, 0.ring is played
