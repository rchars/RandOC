#!/bin/bash


if [[ "$1" == '' ]]
	then
		echo 'Usage: ./oc.sh saveLocation [display]
		echo 'No save location passed - quitting !'
		exit -1
	fi


saveLocation="$1"


if [[ "$2" == '' ]]
	then
		echo 'No display passed - using :0'
		theDisplay=':0'
	else
		theDisplay="$2"
	fi


minorsArr=($(grep -o 'Device Minor.*[0-9]$' /proc/driver/nvidia/gpus/*/information | grep -o '.$'))
modelsArr=($(grep 'Model' /proc/driver/nvidia/gpus/*/information | grep -o 'NVIDIA.*' | tr " " "-"))


echo "Detected GPUS:"
for minor in "${minorsArr[@]}"
	do
		echo "[$minor] => ${modelsArr[$minor]}"
	done


declare -A attribsArr
attribsArr[memClk]="[gpu:#]/GPUMemoryTransferRateOffsetAllPerformanceLevels"
attribsArr[coreClk]="[gpu:#]/GPUGraphicsClockOffsetAllPerformanceLevels"
attribsArr[fanControl]="[gpu:#]/GPUFanControlState"
attribsArr[fanSpeed]="[fan:#]/GPUTargetFanSpeed"


declare -A supportedCommands
supportedCommands[autosave]="doAutoSave"
supportedCommands[print]="doPrint"
supportedCommands[save]="doSave"
supportedCommands[help]="doHelp"
supportedCommands[exit]="doExit"
supportedCommands[set]="doSet"


doPrint() {
	if [[ $firstArgument == '' || $firstArgument == 'all' ]]
		then
			userIndexArr=("${minorsArr[@]}")
		else
			userIndexArr=(${firstArgument//[,]/ })
		fi
	if [[ $secondArgument == '' ]]
		then
			userAttribArr=("${!attribsArr[@]}")
		else
			userAttribArr=(${secondArgument//[,]/ })
		fi
	for minor in "${userIndexArr[@]}"
		do
			echo "[$minor] => ${modelsArr[$minor]}"
			for humanAttrib in "${userAttribArr[@]}"
				do
					attrib="${attribsArr[$humanAttrib]}"
					unhashedAttrib=${attrib//[#]/$minor}
					printf "\t[$humanAttrib] => "
					nvidia-settings -c :0 -q "$unhashedAttrib" -V=errors | grep 'Attribute' | grep -o '\:[[:space:]].*[0-9]\+' | tr -d ': '
				done
			printf '\n'
		done
}


doSet() {
	if [[ $firstArgument == 'all' ]]
		then
			userIndexArr=("${minorsArr[@]}")
		else
			userIndexArr=(${firstArgument//[,]/ })
		fi
	if [[ $secondArgument == 'all' ]]
		then
			userAttribArr=("${!attribsArr[@]}")
		else
			userAttribArr=(${secondArgument//[,]/ })
		fi
	for index in "${userIndexArr[@]}"
		do
			for userAttrib in "${userAttribArr[@]}"
				do
					attrib="${attribsArr[$userAttrib]}"
					if [[ "$attrib" == '' ]]
						then
							echo "No such attrib as \'$userAttrib\'"
							continue
						fi
					unhashedAttrib=${attrib//[#]/$index}
					nvidia-settings -V=errors -c :0 -a "$unhashedAttrib=$thirdArgument"
				done
		done
	if [[ $saveAfterSet == 'on' ]]
		then
			doSave
		fi
}


doSave() {
	echo "Saving to: $saveLocation"
	saveString="#!/bin/bash\nnvidia-settings -c $theDisplay -V=errors"
	for minor in "${minorsArr[@]}"
		do
			for attrib in "${attribsArr[@]}"
				do
					unhashedAttrib=${attrib//[#]/$minor}
					theValue=$(nvidia-settings -c $theDisplay -q "$unhashedAttrib" -V=errors | grep 'Attribute' | grep -o '\:[[:space:]].*[0-9]\+' | tr -d ': ')
					saveString+=" -a $unhashedAttrib=$theValue"
					printf '.'
				done
		done
	printf '\n'
	echo -e $saveString>$saveLocation
	chmod +x $saveLocation
}


doAutoSave() {
	if [[ $saveAfterSet == 'off' ]]
		then
			saveAfterSet='on'
			echo 'autosave on'
		else
			saveAfterSet='off'
			echo 'autosave off'
		fi
}


doHelp() {
	echo 'Usage:
		set <all or comma separated indexes> <all or comma separated attrib names> <value> - set new values
		print <blank or comma separated indexes> <blank or comma spearated attribs> - print attributes and current values
		save <blank> - save current values to file (the file provided by user)
		exit <blank> - exit script
		autosave <blank> - save values to the file after every set
		Examples:
			set all fanSpeed 45
			set 1,2,3 fanControl 0
			print 5,1,6
	'
	echo "Autosave is $saveAfterSet"
}


doExit() {
	endLoop='True'
}


endLoop='False'
saveAfterSet='off'
while [[ $endLoop != 'True' ]]
	do
		read -p 'Command: ' command
		commandArr=($command)
		if [[ -v supportedCommands[${commandArr[0]}] ]]
			then
				firstArgument="${commandArr[1]}"
				secondArgument="${commandArr[2]}"
				thirdArgument="${commandArr[3]}"
				${supportedCommands["${commandArr[0]}"]}
			else
				echo "No such command as '${commandArr[0]}'"
				echo "Type 'help' to get an info'
			fi
	done
