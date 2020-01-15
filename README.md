# piring
Control a school sound system from a Raspberry Pi

## Usage
```
ring [-k|--keyboard [<device>]]
  -k/--keyboard:  Use the keyboard [device] instead of the button
```

## Function
The Normal schedule will ring on every weekday, unless that day is
marked as a No-Bells day. Special schedules will always ring on any
scheduled day, but the Normal schedule will be cancelled, unless at least
one of the Special schedules is an Additional schedule (having a `+` after
the date in `ringdates`).
The (optional) file `ringdates` determines the dates for the Special
schedules and the No-Bells days, the time schedules are defined in the file
`ringtimes`, and the file `ringtones` contains the names of the
corresponding .wav-files.
The optional file `ringalarms` defines what happens when the button is
pushed for a certain minimum length, which can be used for alarms.

Input files `ringtimes`, `ringtones`, `ringdates` and `ringalarms` are read
from the same directory as where the `ring` script resides. These are
checked for proper syntax & semantics, and when OK the program starts and
keeps running, logging output to stdout.

### Format inputfiles
- Lines with `#` as the first character are skipped as comments.
- **ringtimes**: lines with `HH:MMsR` where `s` is Schedule (Normal schedule is
space/empty, and Special schedule codes have an alphabetic character) and
`R` is the Ringtone code. If `R` is space/empty it means it is `0` (the
default), a `-` means a mute for that time regardless of any other schedules.
In general, the `R` matches the first position of lines with the filename
of a `.wav` sound file in the `ringtones` file. R is numerical if not empty or
`-`. All characters after position 7 are ignored as a comment.
- **ringtones**: lines with `Rfilename`, where `R` is the numerical Ringtone
code (0 is the Normal ringtone by default) and 'filename' is the filesystem
location of a .wav file.
- **ringdates** (optional): lines of `YYYY-MM-DDis` or
`YYYY-MM-DD/YYYY-MM-DDis` where `s` is space/empty for No-Bells dates or the
alphabetical Special schedule code, and `i` can be empty/space or `+` (means in
addition to the Normal schedule, otherwise the Normal schedule is replaced by
the Speciak schedule). The double date format is the beginning and end of a
date range. There can be multiple Special schedules for the same date, and
all get rung, even if that date is also a No-Bells date.
All characters after position 12 resp. 23 are ignored as a comment.
- **ringalarms** (optional): lines with `Sfilename`, where `S` at the first
character is the minimum number of seconds the button needs to be
pressed for the `.wav` alarmtone in `filename` to be played. If `S` is `0`
then the tone is played whenever the amp is switched on.

## Required
wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay) date
[control:tmux] [keyboard:evdev grep sudo coreutils(ls head)]

## Deployment
To have it autostart on reboot, the script `ringatreboot` can be called from
cron at reboot (see `ringcrontab` for an example). Alternatively, `ring` can
just be called and the output directed to a file, like: `ring >ring.log`

## License
GPLv3+
