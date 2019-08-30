#!/bin/bash
set +v
# ring - Ring the bell at the right time and control the relay
# Usage: ring
# Reads ringdates for exeptions and ringtimes, format:
#   Ringdates: 'YYYY-MM-DD d' where 'd' is the Day: X: No School, L: Late Start
#   Ringtimes: 'HH:MM s' where 's' is the ring Schedule:
#     N: Normal, E: Elementary Normal, L: Late Start, e: Elementary Late Start
# Required: wiringpi(gpio) coreutils(sleep fold) alsa-utils(aplay) date

# Adjustables
ringdates=$HOME/ringdates ringtimes=$HOME/ringtimes
bell=$HOME/ringbell.wav alarm=$HOME/ringalarm.wav belle=$HOME/ringbelle.wav
relaypin=14 buttonpin=22 ampdelay=3 pollres=.1 alarmlen=3

Log(){ # $1:message $2:time(or not)
	[[ $2 ]] && local datetime="$(date +'%m/%d %H:%M')"
	fold -s <<<"$1 $datetime"
}

Ring(){ # $1:Elementary(or not)  I:$relaypin $ampdelay $time  IO:$relayon
	local elementary= wav=$bell
	[[ $1 ]] && elementary=' Elementary' wav=$belle
	# Turn relay on
	gpio -g write $relaypin 0 && relayon=1 ||
		Log "* Turning relay on failed"
	sleep $ampdelay
	# Ring bell
	aplay "$wav" &>/dev/null && Log "-$e Ring $now" ||
		Log "* Ringing at $now failed"
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
	local numday=$(date '+%u')
	((numday>5)) && return
	local today=$(date +'%Y-%m-%d')
	# Ignore No School dates
	if [[ $xdates == *" $today "* ]]
	then
		[[ $now = '00:00' ]] && Log "- $today No School day"
		return
	fi
	if [[ $ldates == *" $today "* ]]
	then # Late Start day
		[[ $now = '00:00' ]] && Log "- $today Late Start day"
		[[ $ltimes == *" $now "* ]] && Ring
		[[ $eltimes == *" $now "* ]] && Ring e
	else # Normal day
		[[ $now = '00:00' ]] && Log "- $today Normal day"
		[[ $ntimes == *" $now "* ]] && Ring
		[[ $entimes == *" $now "* ]] && Ring E
	fi
}

# Read files into arrays
mapfile -O 1 -t dates <"$ringdates"
mapfile -O 1 -t times <"$ringtimes"

# Globals
xdates=' ' ldates=' ' ntimes=' ' ltimes=' ' entimes=' ' eltimes=' '
nowold= relayon=0 buttonold=9 buttontime=9999999999 stop=

Log "# Ring program initializing" time
Log "> Amplifier switch-on delay $ampdelay s,  Button polling $pollres s"
Log "> Validating Time information in '$ringtimes'"
error=0
for i in "${!times[@]}"
do # Validate and split times
	line=${times[i]} time=${line%% *} schedule=${line##* }
	[[ ! $line =~ ^[0-9][0-9]:[0-9][0-9]' '.$ ]] &&
		Error "Format should be 'HH:MM s'"
	! date -d "$time" &>/dev/null &&
		Error "Invalid Time: '$time'"
	[[ ! $schedule =~ ^[NELe]$ ]] &&
		Error "Schedule code should be N, E, L, or e, not '$schedule'"
	[[ $schedule = N ]] && ntimes+="$time "
	[[ $schedule = E ]] && entimes+="$time "
	[[ $schedule = L ]] && ltimes+="$time "
	[[ $schedule = e ]] && eltimes+="$time "
done
((error==1)) && s= || s=s
((error)) && Log "$error error$s in $ringtimes"
errors=$error

Log "> Validating Date information in '$ringdates'"
error=0
for i in "${!dates[@]}"
do # Validate and split dates
	line=${dates[i]} date=${line%% *} day=${line##* }
	[[ ! $line =~ ^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' '.$ ]] &&
		Error "Format should be '20YY-DD-MM d'"
	! date -d "$date" &>/dev/null &&
		Error "Invalid Date: '$date'"
	[[ ! $day =~ ^[XL]$ ]] &&
		Error "Day code should be X or L, not '$day'"
	[[ $day = L ]] && ldates+="$date "
	[[ $day = X ]] && xdates+="$date "
done
((error==1)) && s= || s=s
((error)) && Log "* $error error$s in $ringdates"
Log "> Normal schedule:$ntimes"
Log "> Elementary Normal schedule:$entimes"
Log "> Late Start schedule:$ltimes"
Log "> Elementary Late Start schedule:$eltimes"
Log "> No School days:$xdates"
Log "> Late Start days:$ldates"

((errors+=error))
((errors==1)) && s= || s=s
((errors)) &&
	Log "* Total of $errors error$s, not starting Ring program" && exit 1 ||
	Log "> All Times and Dates valid"
#gpio(){ :;} # for testing without gpio installed

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
