#!/bin/bash
set +v
# ring - Ring the bell at the right time and control the relay
# Usage: ring
# Reads ringdates for exeptions and ringtimes, format:
#   Ringdates: 'YYYY-MM-DD s' where 's' is the alphabetical special Schedule
#     code (leave out for No School days)
#   Ringtimes: 'HH:MMsr' where 's' is the corresponding Special schedule code
#     (or space for the Normal schedule) and 'r' is the Ringtone code, which
#     points to the array element in 'ringtones' that specifies the file name
#     (can be left out for the Normal '0' code).
# Workings: Normally, every weekday the Normal schedule will ring, except on
#   dates that are listed in the 'ringdates' file, which follow a special
#   schedule that corresponds to the letter in the 'ringtimes' file.
# Required: wiringpi(gpio) coreutils(sleep fold) alsa-utils(aplay) date

# Adjustables
ringdates=$HOME/ringdates ringtimes=$HOME/ringtimes
ringtones=("$HOME/ringbell.wav" "$HOME/ringbelle.wav" "$HOME/ringding.wav")
alarm=$HOME/ringalarm.wav
relaypin=14 buttonpin=22 ampdelay=3 pollres=.1 alarmlen=3

Log(){ # $1:message $2:time(or not)
	[[ $2 ]] && local datetime="$(date +'%m/%d %H:%M')"
	fold -s <<<"$1 $datetime"
}

Ring(){ # $1:ringcode  I:$ringtones $relaypin $ampdelay $time  IO:$relayon
	local ringcode=0 wav
	# Empty ringcode is 0
	[[ $1 ]] && ringcode=$1
	wav=${ringtones[ringcode]}
	# Turn relay on
	gpio -g write $relaypin 0 && relayon=1 ||
		Log "* Turning relay on failed"
	sleep $ampdelay
	# Ring bell
	aplay "$wav" &>/dev/null && Log "- Ring $ringcode $now" ||
		Log "* Playing $wav at $now failed"
	sleep .1
	# Turn relay off
	gpio -g write $relaypin 1 && relayon=0 ||
		Log "* Turning relay off failed"
}

Error(){ # $1:message  I:$i $line  IO:$error
	((++error))
	Log "* Line $i: '$line' - $1"
}

Button(){ # IO:$relayon
	local button=$(gpio -g read $buttonpin)
	if [[ $button = 1 && $buttonold = 0 ]]
	then # Button pressed in
		# Record the time
		buttontime=$(date +%s)
		# Wait for release of the button
		gpio edge 22 rising
		gpio -g wfi 22 falling
		local buttonlen=$(($(date +%s)-buttontime))
		if ((buttonlen>alarmlen))
		then # Long enough to sound the alarm
			((!relayon)) &&
				gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time
			Log "- ALARM!" time
			while :
			do aplay "$alarm" &>/dev/null
			done &
			stop=$!
		else # Toggle relay
			if ((relayon))
			then
				# Stop the alarm if it is on
				[[ $stop ]] && kill $stop && killall aplay
				stop=
				gpio -g write $relaypin 1 && relayon=0 && Log "- Amplifier off" time ||
					Log "* Unable to switch off the relay"
			else
				gpio -g write $relaypin 0 && relayon=1 && Log "- Amplifier on" time ||
					Log "* Unable to switch on the relay"
			fi
		fi
	fi
	buttonold=$button
}

Bellcheck(){ # I:$xdates $ldates $ltimes $ntimes  IO:$nowold
	local now=$(date +'%H:%M')
	# Ignore if this time has been checked earlier
	[[ $now = $nowold ]] && return
	nowold=$now
	# Ignore Sat&Sun (6&7)
	local numday=$(date '+%u') i day schedule
	((numday>5)) && return
	local today=$(date +'%Y-%m-%d')
	for i in "${!specialdates[@]}"
	do
		if [[ "${specialdates[$i]} " == *" $today "* ]]
		then
			[[ $i = _ ]] && day='No School' || day="'$i'"
			[[ $now = '00:00' ]] && Log "- $today $day day"
			[[ $i = _ ]] && return
			[[ "${schedules[$i]} " == *" $now "* ]] &&
				Ring "${ringcodes[$now$i]}" && return
		fi
	done
	[[ "${schedules[_]} " == *" $now "* ]] && Ring "${ringcodes[$now]}"
}

# Read files into arrays
mapfile -O 1 -t dates <"$ringdates"
mapfile -O 1 -t times <"$ringtimes"

# Globals
declare -A schedules ringcodes specialdates
normalschedule= nowold= relayon=0 buttonold=9 buttontime=9999999999 stop=

Log "# Ring program initializing" time
Log "> Amplifier switch-on delay $ampdelay s,  Button polling $pollres s"
Log "> Validating Time information in '$ringtimes'"
error=0

for i in "${!times[@]}"
do # Validate and store times
	line=${times[i]} time=${line:0:5} schedule=${line:5:1} ringcode=${line:6:1}
	! date -d "$time" &>/dev/null &&
		Error "Invalid Time: '$time'"
	# Use underscore for the Normal schedule (schedule is empty or space)
	[[ -z $schedule || $schedule = ' ' ]] && schedule='_'
	[[ ! $schedule =~ ^[_a-zA-Z]$ ]] &&
		Error "Schedule should be a upper or lower case letter, not '$schedule'"
	schedules[$schedule]+=" $time"
	[[ $ringcode && ! $ringcode = ' ' ]] || ringcode=0
	[[ ! $ringcode =~ ^[0-9]$ ]] &&
		Error "Ringcode should be single digit number, not '$ringcode'"
	((ringcode>${#ringtones[@]})) &&
		Error "Ringcode is not defined, add .wav files to array 'ringtones'"
	# Only store ringcodes that are not 0
	[[ $schedule = _ ]] && schedule=
	((ringcode)) && ringcodes[$time$schedule]=$ringcode
done
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringtimes"
errors=$error

Log "> Validating Date information in '$ringdates'"
error=0
for i in "${!dates[@]}"
do # Validate and split dates
	line=${dates[i]} date=${line:0:10} empty=${line:10:1} schedule=${line:11:1}
	[[ ! $date =~ ^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$ ]] &&
		Error "Date format should be '20YY-DD-MM'"
	! date -d "$date" &>/dev/null &&
		Error "Invalid Date: '$date'"
	[[ $empty && ! $empty = ' ' ]] &&
		Error "There must be 1 space after the date, not '$empty'"
	# Use underscore for No School (schedule is empty or space)
	[[ $schedule && ! $schedule = ' ' ]] || schedule='_'
	[[ ! $schedule =~ ^[_a-zA-Z]$ ]] &&
		Error "Schedule should be a upper or lower case letter, not '$schedule'"
	specialdates[$schedule]+=" $date"
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringdates"
for i in "${!schedules[@]}"
do
	[[ $i = _ ]] && s=Normal || s="'$i'"
	Log "> $s schedule:${schedules[$i]}"
done
r="Ringcodes:"
for i in "${!ringcodes[@]}"
do r+=" $i=${ringcodes[$i]}"
done
Log "> $r"
for i in "${!specialdates[@]}"
do
	[[ $i = _ ]] && d='No School' || d="'$i'"
	Log "> $d dates:${specialdates[$i]}"
done

((errors+=error))
((errors==1)) && s= || s=s
((errors)) &&
	Log "* Total of $errors error$s, not starting Ring program" && exit 1 ||
	Log "> All Times and Dates valid"
gpio(){ :;} # for testing without gpio installed

# Setting up pins
! gpio export $relaypin out &&
	Log "* Setting up relay pin $relaypin for output failed" && exit 2 ||
	Log "> Relay pin $relaypin used for output"
! gpio export $buttonpin in &&
	Log "* Setting up button pin $buttonpin for input failed" ||
	Log "> Button pin $buttonpin used for input"
gpio -g mode $buttonpin down
gpio -g write $relaypin 1 && relayon=0 ||
	Log "* Turning relay off failed"
Log "# Ring program started" time
trap "gpio -g write $relaypin 1; gpio unexportall; Log; Log '# Quit' time" \
		QUIT EXIT

# Main loop
while :
do
	Button
	Bellcheck
	sleep $pollres
done
