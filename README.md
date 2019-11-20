# piring
Control a school bell system from a Raspberry Pi

## Usage
```
ring [-k|--keyboard]
  -k/--keyboard:  Use the keyboard instead of the button
```

Reads input files `ringtimes`, `ringtones`, `ringdates` and `ringalarms` from
the same directory as where the `ring` script resides. These are checked for
proper syntax & semantics, and when OK the program starts and keeps running,
logging output to stdout.

### Format
- Lines with `#` as the first character are skipped as comments.
- **ringtimes**: lines with `HH:MMsR` where `s` is Schedule (Normal schedule is
space/empty, and Special schedule codes have an alphabetic character) and
`R` is the Ringtone code. If `R` is space/empty it means it is `0` (the
default), a `-` means a mute for that time regardless of other schedules.
In general, the `R` matches the first position of lines with the filename
of a `.wav` sound file in the `ringtones` file.
All characters after position 7 are ignored as a comment.
- **ringtones**: lines with `Rfilename`, where `R` is the numerical Ringtone
code (0 is the Normal ringtone by default) and 'filename' is the filesystem
location of a .wav file.
- **ringdates** (optional): lines of `YYYY-MM-DDis` or
`YYYY-MM-DD/YYYY-MM-DDis` where `s` is space/empty for No-School dates or the
alphabetical Special schedule code, and `i` can be empty/space or `+` (means it is addition to the Normal schedule, otherwise it replaces the Normal schedule).
The double date format is the beginning and end of a date range.
There can be a single or multiple Special schedules for the same date, and
all get rung, even if that date is also a No-School date.
All characters after position 12 resp. 23 are ignored as a comment.
- **ringalarms** (optional): lines with `Sfilename`, where `S` at the first
character is the minimum number of seconds the button needs to be
pressed for the `.wav` alarmtone in `filename` to be played. If 'S' is '0'
then the tone is played whenever the amp is switched on.

### Workings
Every weekday (except on No-School days) the Normal schedule will ring and
additional schedules (with `+` after the date). On dates with a Special
schedule without a `+` the Normal schedule will not ring.

## Required
wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay) date
[control:tmux] [keyboard:evdev grep sudo coreutils(ls head)]

## Deployment
To have it autostart on reboot, the script `ringatreboot` can be called from
cron at reboot (see `ringcrontab` for an example). Alternatively, `ring` can
just be called and the output directed to a file, like: `ring >ring.log`

## License
GPLv3+
