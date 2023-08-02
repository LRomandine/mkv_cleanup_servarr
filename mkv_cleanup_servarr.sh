#!/bin/bash
##############################################################################
# mkv_cleanup_servarr.sh
#  Automatically cleans up video files
#   Repackages into .mkv
#   Removes unwanted subtitle languages
#   Removes unwanted audio languages
#	Sets permissions and ownership
##############################################################################
# Instructions
#  Call with the file or directory to be scanned
#  If a directory is passed, all video files under it will be scanned
#  Examples:
#   ./mkv_cleanup_servarr.sh "/storage/tv/my show/"
#   ./mkv_cleanup_servarr.sh "/storage/tv/my show/my show - season 01/my show - s01e01 - pilot.mp4"
##############################################################################
# Forked from
#  https://github.com/RandomNinjaAtk/Scripts/blob/master/external/MKVCleanup.bash
##############################################################################
# Requirements
#  mkvtoolsnix (mkvmerge)
#  jq
#  ffprobe
##############################################################################
# Changelog
# 0.1.0
#  Initial public release on Github
#  There are many comments from development and testing
##############################################################################
# Change these variables for your use
LOG_FILE=/var/log/mkv_cleanup.log
ERR_FILE=/var/log/mkv_cleanup.err
CSV_FILE=/var/log/mkv_cleanup.csv
CHMOD_CODE="775"
CHOWN_USER="user"
CHOWN_GROUP="group"
PARENT_TV_DIRECTORY="/storage/tv"  # No trailing slash
SKIP_CHMOD=FALSE  # Must be "TRUE" to skip

# More optional variables
VIDEO_MKVCLEANER=TRUE
DRY_RUN=FALSE
VIDEO_LANG="eng"
CONVERTER_OUTPUT_EXTENSION="mkv"  # Changing this will break CHMOD section
CORRECT_UNKNOWN_VIDEO_LANGUAGE=TRUE
REPACKAGE_TO_MKV=TRUE
IGNORE_UNDETERMINED_LANG_SUBTITLES=FALSE
TARGET_DIR="${1}"
OUTPUT_QUIET=FALSE
if [[ "${sonarr_eventtype}" == "Test" ]];then
	echo "INFO: Sonarr test event, exiting successfully"
	exit 0
fi
if [[ "${radarr_eventtype}" == "Test" ]];then
        echo "INFO: Radarr test event, exiting successfully"
        exit 0
fi
if [[ "${sonarr_eventtype}" != "" && "${sonarr_eventtype}" != "Download" ]];then
	echo "ERROR: Sonarr event type '${sonarr_eventtype}' not supported."
	echo "ERROR: Sonarr event type must be 'Test' or 'Download'."
	exit 1
fi
if [[ "${radarr_eventtype}" != "" && "${radarr_eventtype}" != "Download" ]];then
        echo "ERROR: Radarr event type '${radarr_eventtype}' not supported."
        echo "ERROR: Radarr event type must be 'Test' or 'Download'."
        exit 1
fi
if [[ "${sonarr_episodefile_path}" != "" ]];then
	TARGET_DIR="${sonarr_episodefile_path}"
fi
if [[ "${radarr_moviefile_path}" != "" ]];then
        TARGET_DIR="${radarr_moviefile_path}"
fi
if [[ "${TARGET_DIR}" == "" ]];then
	echo "ERROR: No path specified through 'sonarr_episodefile_path', 'radarr_moviefile_path', or '\$1'"
	exit 1
fi
if [[ ! -f "${TARGET_DIR}" && ! -d "${TARGET_DIR}" ]];then
	echo "ERROR: Given target of '${TARGET_DIR}' is neither a file or directory."
        exit 1
fi
if [[ "${2}" == TRUE || "${2}" == FALSE ]];then
	OUTPUT_QUIET="${2}"
fi
#===============FUNCTIONS==============
#check for required applications
if [ ${OUTPUT_QUIET} != TRUE ]; then
	echo ""
	echo "=========================="
	echo "INFO: Begin checking for required applications"
	echo "CHECK: for mkvmerge utility"
fi
if [ ! -x "$(command -v mkvmerge)" ]; then
	echo "ERROR: mkvmerge utility not installed"
	exit 1
else
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo "SUCCESS: mkvmerge installed"
	fi
fi
if [ ${OUTPUT_QUIET} != TRUE ]; then
	echo "CHECK: for jq utility"
fi
if [ ! -x "$(command -v jq)" ]; then
	echo "ERROR: jq package not installed"
	exit 1
else
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo "SUCCESS: jq installed"
	fi
fi
if [ ${OUTPUT_QUIET} != TRUE ]; then
	echo "CHECK: for ffprobe utility"
fi
if [ ! -x "$(command -v ffprobe)" ]; then
	echo "ERROR: ffprobe package not installed"
	exit 1
else
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo "SUCCESS: ffprobe installed"
	fi
fi
filecount=$(find "${TARGET_DIR}" -type f -iregex ".*/.*\.\(mkv\|mp4\|avi\)" | wc -l)
if [ ${OUTPUT_QUIET} != TRUE ]; then
	echo "=========================="
	echo ""
fi
count=0
find "${TARGET_DIR}" -type f -iregex ".*/.*\.\(mkv\|mp4\|mov\|m4v\|m2ts\|ts\|3gp\|wmv\|avi\|mpg\)" -print0 | while IFS= read -r -d '' video; do
	count=$(($count+1))
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo ""
		echo "===================================================="
	fi
	filename="$(basename "$video")"
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo "Begin processing $count of $filecount: $filename"
		echo "Checking for audio/subtitle tracks"
	fi
	tracks=$(mkvmerge -J "$video" )
	if [ ! -z "${tracks}" ]; then
		# video tracks
		VideoTrack=$(echo "${tracks}" | jq ".tracks[] | select(.type==\"video\") | .id")
		VideoTrackCount=$(echo "${tracks}" |  jq ".tracks[] | select(.type==\"video\") | .id" | wc -l)
		# video preferred language
		VideoTrackLanguage=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"video\") and select(.properties.language==\"${VIDEO_LANG}\")) | .id")
		# audio tracks
		AudioTracks=$(echo "${tracks}" | jq ".tracks[] | select(.type==\"audio\") | .id")
		AudioTracksCount=$(echo "${tracks}" | jq ".tracks[] | select(.type==\"audio\") | .id" | wc -l)
		# audio preferred language
		#    we allow eng and jpn for anime
		AudioTracksLanguage=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"audio\") and select(.properties.language==\"${VIDEO_LANG}\")) or ((.type==\"audio\") and select(.properties.language==\"jpn\"))) | .id")
		#AudioTracksLanguage=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language==\"${VIDEO_LANG}\") and select(.properties.language==\"jpn\")) | .id")
		#AudioTracksLanguageCount=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language==\"${VIDEO_LANG}\") and select(.properties.language==\"jpn\")) | .id" | wc -l)
		AudioTracksLanguageCount=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"audio\") and select(.properties.language==\"${VIDEO_LANG}\")) or ((.type==\"audio\") and select(.properties.language==\"jpn\"))) | .id" | wc -l)
		# audio unkown laguage
		if [ ${CORRECT_UNKNOWN_VIDEO_LANGUAGE} = TRUE ]; then
			AudioTracksLanguageUND=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language==\"und\")) | .id")
			AudioTracksLanguageUNDCount=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language==\"und\")) | .id" | wc -l)
			AudioTracksLanguageNull=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language==null)) | .id")
			AudioTracksLanguageNullCount=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language==null)) | .id" | wc -l)
		else
			AudioTracksLanguageUND=""
			AudioTracksLanguageUNDCount=0
			AudioTracksLanguageNull=""
			AudioTracksLanguageNullCount=0
		fi
		# audio foreign language
		if [ ${CORRECT_UNKNOWN_VIDEO_LANGUAGE} = TRUE ]; then
			AudioTracksLanguageForeignCount=$(echo "${tracks}" | jq ".tracks[] | select((.type==\"audio\") and select(.properties.language!=\"${VIDEO_LANG}\")) | .id" | wc -l)		
		else
			AudioTracksLanguageForeignCount=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"audio\") and select(.properties.language!=\"${VIDEO_LANG}\")) or ((.type==\"audio\") and select(.properties.language!=\"und\"))) | .id" | wc -l)		
		fi
		# subtitle tracks
		SubtitleTracks=$(echo "${tracks}" | jq ".tracks[] | select(.type==\"subtitles\") | .id")	
		SubtitleTracksCount=$(echo "${tracks}" | jq ".tracks[] | select(.type==\"subtitles\") | .id" | wc -l)
		# subtitle preferred langauge
		SubtitleTracksLanguage=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"subtitles\") and select(.properties.language==\"${VIDEO_LANG}\")) and ((.type==\"subtitles\") and (select(.properties.track_name==\"SDH\" | not)))) | .id")
		SubtitleTracksLanguageCount=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"subtitles\") and select(.properties.language==\"${VIDEO_LANG}\")) and ((.type==\"subtitles\") and (select(.properties.track_name==\"SDH\" | not)))) | .id" | wc -l)
		SubtitleTracksLanguageUND=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"subtitles\") and select(.properties.language==\"und\")) and ((.type==\"subtitles\") and (select(.properties.track_name==\"SDH\" | not)))) | .id")
		SubtitleTracksLanguageUNDCount=$(echo "${tracks}" | jq ".tracks[] | select(((.type==\"subtitles\") and select(.properties.language==\"und\")) and ((.type==\"subtitles\") and (select(.properties.track_name==\"SDH\" | not)))) | .id" | wc -l)
	else
		echo "ERROR: ffprobe failed to read tracks and set values"
		# rm "$video" && echo "INFO: deleted: $video"
	fi	
	
	# Check for video track
	if [ -z "${VideoTrack}" ]; then
		echo "ERROR: no video track found"
		# rm "$video" && echo "INFO: deleted: $filename"
		continue
	else
		if [ ${OUTPUT_QUIET} != TRUE ]; then
			echo "$VideoTrackCount video track found!"
		fi
	fi
	
	# Check for audio track
	if [ -z "${AudioTracks}" ]; then
		echo "ERROR: no audio tracks found"
		# rm "$video" && echo "INFO: deleted: $filename"
		continue
	else
		if [ ${OUTPUT_QUIET} != TRUE ]; then
			echo "$AudioTracksCount audio tracks found!"
		fi
	fi
	
	# Check for audio track
	if [ ! -z "${SubtitleTracks}" ]; then
		if [ ${OUTPUT_QUIET} != TRUE ]; then
			echo "$SubtitleTracksCount subtitle tracks found!"
		fi
	fi
	
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo "Checking for \"${VIDEO_LANG}\" audio/video/subtitle tracks"
	fi
	if [ ! -z "$AudioTracksLanguage" ] || [ ! -z "$SubtitleTracksLanguage" ]; then
		if [ ! ${VIDEO_MKVCLEANER} = TRUE ]; then
			if [ ${OUTPUT_QUIET} != TRUE ]; then
				echo "INFO: No \"${VIDEO_LANG}\" audio or subtitle tracks found..."
			fi
			# rm "$video" && echo "INFO: deleted: $filename"
			continue
		else
			if [ ! -z "$AudioTracksLanguage" ] || [ ! -z "$SubtitleTracksLanguage" ] || [ ! -z "$AudioTracksLanguageUND" ] || [ ! -z "$AudioTracksLanguageNull" ]; then
				sleep 0.1
			else
				echo "ERROR: No \"${VIDEO_LANG}\" or \"Unknown\" audio tracks found..."
				echo "ERROR: No \"${VIDEO_LANG}\" subtitle tracks found..."
				# rm "$video" && echo "INFO: deleted: $filename"
				continue
			fi
		fi
	else
		if [ ! ${VIDEO_MKVCLEANER} = TRUE ]; then
			if [ ! -z "$AudioTracksLanguage" ]; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "$AudioTracksLanguageCount \"${VIDEO_LANG}\" audio track found..."
				fi
			fi
			if [ ! -z "$SubtitleTracksLanguage" ]; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "$SubtitleTracksLanguageCount \"${VIDEO_LANG}\" subtitle track found..."
				fi
			fi
		fi
	fi	
	
	retagaudiocount=0
	if [ ${VIDEO_MKVCLEANER} = TRUE ]; then	
		# Check for unwanted audio tracks and remove/re-label as needed...
		if [ ! -z "$AudioTracksLanguage" ] || [ ! -z "$AudioTracksLanguageUND" ] || [ ! -z "$AudioTracksLanguageNull" ] || [ ! -z "$AudioTracksLanguageForeignCount" ]; then
			if [ $AudioTracksCount -ne $AudioTracksLanguageCount ]; then
				RemoveAudioTracks="true"
				if [ ! -z "$AudioTracksLanguage" ]; then
					MKVaudio=" -a ${VIDEO_LANG}"
					if [ ${OUTPUT_QUIET} != TRUE ]; then
						echo "$AudioTracksLanguageCount audio tracks found!"
					fi
					unwantedaudiocount=$(($AudioTracksCount-$AudioTracksLanguageCount))
					if [ $AudioTracksLanguageCount -ne $AudioTracksCount ]; then
						unwantedaudio="true"
					fi
				# Remove non-Eng and non-Jpn audio
				elif [ ! -z "$AudioTracksLanguageForeignCount" ] && [ $AudioTracksCount -gt 1 ]; then
                                        MKVaudio=" -a ${VIDEO_LANG}"
                                        if [ ${OUTPUT_QUIET} != TRUE ]; then
                                                echo "$AudioTracksLanguageForeignCount audio tracks found!"
                                        fi
                                        unwantedaudiocount=$(($AudioTracksCount-$AudioTracksLanguageForeignCount))
                                        if [ $AudioTracksLanguageCount -ne $AudioTracksCount ]; then
                                                unwantedaudio="true"
                                        fi
				elif [ ! -z "$AudioTracksLanguageUND" ]; then
					for I in $AudioTracksLanguageUND
					do
						OUT=$OUT" -a $I --language $I:${VIDEO_LANG}"
					done
					MKVaudio="$OUT"
					if [ ${OUTPUT_QUIET} != TRUE ]; then
						echo "$AudioTracksLanguageUNDCount \"unknown\" audio tracks found, re-tagging as \"${VIDEO_LANG}\""
					fi
					retagaudiocount=$(($retagaudiocount+1))
					unwantedaudiocount=$(($AudioTracksCount-$AudioTracksLanguageUNDCount))
					if [ $AudioTracksLanguageUNDCount -ne $AudioTracksCount ]; then
						unwantedaudio="true"
					fi
				elif [ ! -z "$AudioTracksLanguageNull" ]; then
					for I in $AudioTracksLanguageNull
					do
						OUT=$OUT" -a $I --language $I:${VIDEO_LANG}"
					done
					MKVaudio="$OUT"
					if [ ${OUTPUT_QUIET} != TRUE ]; then
						echo "$AudioTracksLanguageNullCount \"unknown\" audio tracks found, re-tagging as \"${VIDEO_LANG}\""
					fi
					retagaudiocount=$(($retagaudiocount+1))
					unwantedaudiocount=$(($AudioTracksCount-$AudioTracksLanguageNullCount))
					if [ $AudioTracksLanguageNullCount -ne $AudioTracksCount ]; then
						unwantedaudio="true"
					fi
				fi
			else
				echo "$AudioTracksLanguageCount audio tracks found!"
				RemoveAudioTracks="false"
				MKVaudio=""
			fi
		elif [ -z "$SubtitleTracksLanguage" ]; then
			if [ ${OUTPUT_QUIET} != TRUE ]; then
				echo "INFO: no \"${VIDEO_LANG}\" subtitle tracks found!"
			fi
			# this next line may produce inintended results, but trying to get the script to repackage files even if no subtitles are found
			RemoveSubtitleTracks="false"
			RemoveAudioTracks="false"
			# this continue may be the cause, it seems to abort current file
			# continue
		else
			foreignaudio="true"
			RemoveSubtitleTracks="false"
			RemoveAudioTracks="false"
			MKVaudio=""
		fi
	
		# Check for unwanted subtitle tracks...
		retagsubtitlecount=0
		if [ $SubtitleTracksCount -ne $SubtitleTracksLanguageCount ]; then
		        RemoveSubtitleTracks="true"
		        if [ ! -z "$SubtitleTracksLanguage" ]; then
		                OUT=" -s "
		                loop="false"
		                for I in $SubtitleTracksLanguage
		                do
                		        if [ "$loop" == "true" ];then
                                		OUT=$OUT",$I"
		                        else
                		                OUT=$OUT"$I"
		                                loop="true"
                		        fi
		                done
		                MKVSubtitle="$OUT"
		                # MKVSubtitle=" -s ${VIDEO_LANG}"
		                if [ ${OUTPUT_QUIET} != TRUE ]; then
		                        echo "$SubtitleTracksLanguageCount subtitle tracks found!"
		                fi
		                unwantedsubtitlecount=$(($SubtitleTracksCount-$SubtitleTracksLanguageCount))
		        fi
		        if [ ! -z "$SubtitleTracksLanguageUND" ];then
		                for I in $SubtitleTracksLanguageUND
                		do
		                        OUT=$OUT" -s $I --language $I:${VIDEO_LANG}"
                		done
		                MKVSubtitle="$OUT"
		                if [ ${OUTPUT_QUIET} != TRUE ]; then
		                        echo "$SubtitleTracksLanguageUNDCount \"unknown\" subtitle tracks found, re-tagging as \"${VIDEO_LANG}\""
		                fi
		                retagsubtitlecount=$(($retagsubtitlecount+1))
		                unwantedsubtitlecount=$(($SubtitleTracksCount-$SubtitleTracksLanguageUNDCount))
		        fi
			if [ $SubtitleTracksLanguageCount -ne $SubtitleTracksCount ]; then
	                        unwantedsubtitle="true"
                        fi
			if [ $SubtitleTracksLanguageUNDCount -ne $SubtitleTracksCount ]; then
	                        unwantedsubtitle="true"
			fi
		else
		        if [ ${OUTPUT_QUIET} != TRUE ]; then
		                echo "$SubtitleTracksLanguageCount subtitle tracks found!"
		        fi
		        RemoveSubtitleTracks="false"
		        MKVSubtitle=""
		fi
		# If there are no subtitles to save mkvmerge will default to copying all of them if we do not specify any, so we must specify none
		if [ -z "$MKVSubtitle" ] && [ $RemoveSubtitleTracks == "true" ];then
		        MKVSubtitle=" -S "
		fi
		
		# Correct video language, if needed...
		retagvideocount=0
		if [ -z "$VideoTrackLanguage" ]; then	
			if [ ! -z "$AudioTracksLanguage" ] || [ ! -z "$AudioTracksLanguageUND" ] || [ ! -z "$AudioTracksLanguageNull" ]; then
				SetVideoLanguage="true"
				if [ "${RemoveAudioTracks}" = true ] || [ "${RemoveSubtitleTracks}" = true ]; then
					if [ ${OUTPUT_QUIET} != TRUE ]; then
						echo "$VideoTrackCount \"unknown\" video language track found, re-tagging as \"${VIDEO_LANG}\""
					fi
					retagvideocount=$(($retagvideocount+1))
				fi
				MKVvideo=" -d ${VideoTrack} --language ${VideoTrack}:${VIDEO_LANG}"
			else
				foreignvideo="true"
				SetVideoLanguage="false"
				MKVvideo=""
			fi
		else
			if [ ${OUTPUT_QUIET} != TRUE ]; then
				echo "$VideoTrackCount video tracks found!"
			fi
			SetVideoLanguage="false"
			MKVvideo=""
		fi
		
		# Display foreign audio track counts
		if [ "$foreignaudio" = true ] || [ "$foreignvideo" = true ]; then
			if [ ${OUTPUT_QUIET} != TRUE ]; then
				echo "Checking for \"foreign\" audio/video tracks"
			fi
			if [ "$foreignvideo" = true ]; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "$VideoTrackCount video track found!"
				fi
				foreignvideo="false"
			fi
			if [ "$foreignaudio" = true ]; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "$AudioTracksLanguageForeignCount audio tracks found!"
				fi
				foreignaudio="false"
			fi
		fi
		
		# Display unwanted audio/subtitle track counts
		CSV_LOG=""
		if [ "$unwantedaudio" = true ] || [ "$unwantedsubtitle" = true ]; then
			if [ ${OUTPUT_QUIET} != TRUE ]; then
				echo "Checking for unwanted \"not: ${VIDEO_LANG}\" audio/subtitle tracks"
			fi
			echo "${filename}" >> ${LOG_FILE}
			if [ "$unwantedaudio" = true ]; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "$unwantedaudiocount audio tracks to remove..."
				fi
				echo "    $unwantedaudiocount audio tracks to remove..." >> ${LOG_FILE}
				CSV_LOG="${CSV_LOG},${unwantedaudiocount} audio tracks to remove"
				unwantedaudio="false"
			fi	
			if [ "$unwantedsubtitle" = true ]; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "$unwantedsubtitlecount subtitle tracks to remove..."
				fi
				echo "    $unwantedsubtitlecount subtitle tracks to remove..." >> ${LOG_FILE}
				CSV_LOG="${CSV_LOG},${unwantedsubtitlecount} subtitle tracks to remove"
				unwantedsubtitle="false"
			fi
		fi

		if (( $retagvideocount > 0 )) || (( $retagaudiocount > 0 )) || (( $retagsubtitlecount > 0 ));then
			if (( $retagvideocount > 0 ));then
				CSV_LOG="${CSV_LOG},${retagvideocount} video track retagging"
			fi
			if (( $retagaudiocount > 0 ));then
				CSV_LOG="${CSV_LOG},${retagaudiocount} audio track retagging"
			fi
			if (( $retagsubtitlecount > 0 ));then
				CSV_LOG="${CSV_LOG},${retagsubtitlecount} subtitle track retagging"
			fi
		fi
		
		if [ "${RemoveAudioTracks}" = false ] && [ "${RemoveSubtitleTracks}" = false ]; then
			if find "$video" -type f -iname "*.${CONVERTER_OUTPUT_EXTENSION}" | read; then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "INFO: Video passed all checks, no processing needed"
				fi
				touch "$video"
				continue
			else
				if [ ${REPACKAGE_TO_MKV} == TRUE ]; then
					if [ ${OUTPUT_QUIET} != TRUE ]; then
						echo "INFO: Video passed all checks, but is in the incorrect container, repackaging as mkv..."
					fi
					echo -e "${filename}\n    incorrect container, repackaging as mkv" >> ${LOG_FILE}
					CSV_LOG="${CSV_LOG},incorrect container, repackaging as mkv"
					MKVvideo=" -d ${VideoTrack} --language ${VideoTrack}:${VIDEO_LANG}"
					MKVaudio=" -a ${VIDEO_LANG}"
					MKVSubtitle=" -s ${VIDEO_LANG}"
				else
					continue
				fi
			fi
		fi
		if [ "$CSV_LOG" != "" ];then
			echo "${filename}${CSV_LOG}" >> ${CSV_FILE}
		fi

		basefilename="${video%.*}"
		if [ ${DRY_RUN} != TRUE ]; then
			#OUTPUT=$(mkvmerge -q --no-global-tags --title "" -o "${basefilename}.merged.mkv"${MKVvideo}${MKVaudio}${MKVSubtitle} "$video" 2>&1)
			OUTPUT=$(mkvmerge -q --no-global-tags --title "" -o "${basefilename}.merged.mkv"${MKVvideo}${MKVaudio}${MKVSubtitle} "$video" )
			mkvmerge --no-global-tags --title "" -o "${basefilename}.merged.mkv"${MKVvideo}${MKVaudio}${MKVSubtitle} "$video"
			if [[ $? == 0 ]];then
				if [ ${OUTPUT_QUIET} != TRUE ]; then
					echo "SUCCESS: mkvmerge complete"
					echo "INFO: Options used:${MKVvideo}${MKVaudio}${MKVSubtitle} \"${video}\""
					echo "INFO: Output is ${OUTPUT}"
				fi
				mv "$video" "$video.original"
				mv "${basefilename}.merged.mkv" "${basefilename}.mkv"
				rm "$video.original"
				if [ ${OUTPUT_QUIET} != TRUE ]; then
                                        echo "INFO: Cleaned up temp files"
                                fi
			else
				if [[ `echo "${OUTPUT}" | grep -i 'error'` != "" ]];then
					echo "ERROR: mkvmerge failed on ${video} with error output ${OUTPUT}" | tee -a "${ERR_FILE}"
					rm "${basefilename}.merged.mkv"
					if [ ${OUTPUT_QUIET} != TRUE ]; then
						echo "INFO: Options used:${MKVvideo}${MKVaudio}${MKVSubtitle}"
						echo "INFO: deleted: ${basefilename}.merged.mkv"
					fi
					continue
				else
					if [[ `echo "${OUTPUT}" | grep -i 'audio/video synchronization may have been lost'` != "" ]];then
						#likely an AVI or MPG with weird time stuff on audio, ignore it
						if [ ${OUTPUT_QUIET} != TRUE ]; then
		                                        echo "SUCCESS: mkvmerge complete"
                		                        echo "INFO: Options used:${MKVvideo}${MKVaudio}${MKVSubtitle}"
		                                fi
                		                mv "$video" "$video.original"
                                		mv "${basefilename}.merged.mkv" "${basefilename}.mkv"
		                                rm "$video.original"
                		                if [ ${OUTPUT_QUIET} != TRUE ]; then
                                		        echo "INFO: Cleaned up temp files"
		                                fi
					else
						# weird warning?
						echo "ERROR: mkvmerge failed on ${video} with error output ${OUTPUT}" | tee -a "${ERR_FILE}"
	                                        rm "${basefilename}.merged.mkv"
        	                                if [ ${OUTPUT_QUIET} != TRUE ]; then
                	                                echo "INFO: Options used:${MKVvideo}${MKVaudio}${MKVSubtitle}"
                        	                        echo "INFO: deleted: ${basefilename}.merged.mkv"
                                	        fi
                                        	continue
					fi
				fi
			fi
		else
			# We ignore quiet mode for dry_run to remind user we are in dry run mode
			echo "INFO: dry run, not processing file"
			if [ ${OUTPUT_QUIET} != TRUE ]; then
				echo "INFO: Options used:${MKVvideo}${MKVaudio}${MKVSubtitle}"
			fi
		fi
	fi
	if [ ${OUTPUT_QUIET} != TRUE ]; then
		echo "===================================================="
	fi
	sleep 2
done

if [ ${OUTPUT_QUIET} != TRUE ]; then
	echo "INFO: Finished processing $count files"
fi

if [ ${SKIP_CHMOD} != TRUE ]; then
	# Fix permissions on the file
	find "${TARGET_DIR}" -type f -iregex ".*/.*\.\(mkv\)" -print0 | while IFS= read -r -d '' video; do
		if [[ "${TARGET_DIR}" != "" && "${TARGET_DIR}" != "/" && `echo "${TARGET_DIR}" | cut -c -2` != "/ " ]];then
		# We already only search for MKV files so no need to change the file extension or anything
		if [[ -f "${video}" ]];then
				sudo chmod -R ${CHMOD_CODE} "${video}"
				sudo chown -R ${CHOWN_USER}:${CHOWN_GROUP} "${video}"
		fi
			if [[ "${PARENT}" != "${PARENT_TV_DIRECTORY}" && "${PARENT}" != "" && "${PARENT}" != "/" && "${PARENT}" != "." ]];then
				# This will catch new TV shows parent folder (season folder) but not pointlessly chown the whole TV folder
				sudo chmod -R ${CHMOD_CODE} "${PARENT}"
				sudo chown -R ${CHOWN_USER}:${CHOWN_GROUP} "${PARENT}"
			fi
			# We could chown a new shows's root folder (series folder) but that does not happen often and when it does the daily find script will catch it, better tha CHMOD'ing the whole thing AGAIN
		fi
	done
fi

# script complete, now exiting
exit $?
