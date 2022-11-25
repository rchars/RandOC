#!/bin/bash


if [[ "$1" == '' ]]
	then
		echo 'Usage: ./oc.sh saveLocation [display]'
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
		nvidia-smi -i "$minor" -pm 1
		# nvidia-settings -V=error -a "[gpu:$minor]/GPUPowerMizerMode=1"
		nvidia-settings -a "[gpu:$minor]/GPUPowerMizerMode=1"
	done


declare -A nsAttribsArr
nsAttribsArr[memOffset]="[gpu:#]/GPUMemoryTransferRateOffsetAllPerformanceLevels"
nsAttribsArr[coreOffset]="[gpu:#]/GPUGraphicsClockOffsetAllPerformanceLevels"
nsAttribsArr[powerMizer]="[gpu:#]/GPUPowerMizerMode"
nsAttribsArr[fanControl]="[gpu:#]/GPUFanControlState"
nsAttribsArr[fanSpeed]="[fan:#]/GPUTargetFanSpeed"


# nvidia-smi --query-gpu=clocks.gr,clocks.mem,clocks.sm --format=csv,noheader,nounits -i 0
declare -A nnAttribsArr
nnAttribsArr[pMode]="-i # -pm"
nnAttribsArr[lockClk]="-i # -lgc"
nnAttribsArr[powerLimit]="-i # -pl"

formatGpuString="--format=csv,noheader,nounits -i #"
declare -A nnCommandsArr
nnCommandsArr[pMode]="--query-gpu=persistence_mode $formatGpuString"
nnCommandsArr[lockClk]="--query-gpu=clocks.gr $formatGpuString"
nnCommandsArr[powerLimit]="--query-gpu=power.limit $formatGpuString"


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
			userAttribArr=("${!nsAttribsArr[@]}" "${!nnCommandsArr[@]}")
		else
			userAttribArr=(${secondArgument//[,]/ })
		fi
	for minor in "${userIndexArr[@]}"
		do
			echo "[$minor] => ${modelsArr[$minor]}"
			for humanAttrib in "${userAttribArr[@]}"
				do
					if [[ -v nsAttribsArr[$humanAttrib] ]]
						then
							attrib="${nsAttribsArr[$humanAttrib]}"
							unhashedAttrib=${attrib//[#]/$minor}
							printf "\t[$humanAttrib] => "
							nvidia-settings -c :0 -tq "$unhashedAttrib" -V=errors
						elif [[ -v nnCommandsArr[$humanAttrib] ]]
							then
								attrib="${nnCommandsArr[$humanAttrib]}"
								unhashedAttrib=${attrib//[#]/$minor}
								printf "\t[$humanAttrib] => "
								nvidia-smi $unhashedAttrib
						else
							echo "Unknown attribute: $humanAttrib"
						fi
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
			userAttribArr=("${!nsAttribsArr[@]}" "${!nnCommandsArr[@]}")
		else
			userAttribArr=(${secondArgument//[,]/ })
		fi
	for index in "${userIndexArr[@]}"
		do
			for userAttrib in "${userAttribArr[@]}"
				do
					if [[ -v nsAttribsArr[$userAttrib] ]]
						then
							attrib="${nsAttribsArr[$userAttrib]}"
							unhashedAttrib=${attrib//[#]/$index}
							nvidia-settings -V=errors -c :0 -a "$unhashedAttrib=$thirdArgument"
						elif [[ -v nnAttribsArr[$userAttrib] ]]
							then
								attrib="${nnAttribsArr[$userAttrib]}"
								unhashedAttrib=${attrib//[#]/$index}
								nvidia-smi $unhashedAttrib $thirdArgument
						else
							echo "No such attrib as \'$userAttrib\'"
						fi
				done
		done
	if [[ $saveAfterSet == 'on' ]]
		then
			doSave
		fi
}


doSave() {
	echo "Saving to: $saveLocation"
	saveString="nvidia-settings -c $theDisplay"
	for minor in "${minorsArr[@]}"
		do
			for attrib in "${nsAttribsArr[@]}"
				do
					unhashedAttrib=${attrib//[#]/$minor}
					theValue=$(nvidia-settings -c :0 -tq "$unhashedAttrib" -V=errors)
					saveString+=" -a $unhashedAttrib=$theValue"
					printf '.'
				done
		done
	saveSmi="#!/bin/bash\n"
	for minor in "${minorsArr[@]}"
		do
			for humanAttrib in "${!nnAttribsArr[@]}"
				do
					smiArgs="${nnCommandsArr[$humanAttrib]}"
					unhashedSmiArgs=${smiArgs//[#]/$minor}
					theValue=$(nvidia-smi $unhashedSmiArgs | tr '[:lower:]' '[:upper:]')
					command="${nnAttribsArr[$humanAttrib]}"
					unhashedCommand=${command//[#]/$minor}
					saveSmi+="nvidia-smi $unhashedCommand $theValue\n"
					printf '.'
				done
		done
	printf '\n'
	echo -e $saveSmi>$saveLocation
	echo -e $saveString>>$saveLocation
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
				echo 'Type 'help' to get an info'
			fi
	done
