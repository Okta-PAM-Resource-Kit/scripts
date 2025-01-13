#!/bin/bash +x
#
# OPA session log playback helper.
case "$1" in
        active)
                recpath=/tmp
                cmd="tail -n +1 -f"
                ;;
        inactive)
                recpath=/var/log/sft/sessions
                cmd=cat
                prefix=ssh
                ;;
        *)
                echo "Usage: $0 {active|inactive}"
                exit 1
esac

files=()

OLDIFS=$IFS

IFS=$'\n'

#files+=($(sudo bash -c "cd ${recpath}; ls -1trsh ${prefix}*.asa" | awk '$1 != "total" && $1 != "0" {print $1, $2}'))

for file in $(sudo bash -c "cd ${recpath}; ls -1trh ${prefix}*.asa"); do
#  echo ${file}
  full_path="/var/log/sft/sessions/${file}"
#  echo ${full_path}
  if sudo bash -c "head -c 2048 ${full_path} | grep -q 'pty-req'"; then
    size=$(sudo bash -c "stat --format='%s' ${full_path}")
    IFS=$'~'
    fields=()
    read -ra fields <<< "${file}"
    IFS=$'\n'
    files+=("$size $file")
#    filesmeta+=("${fields[1]} ${fields[4]} ${fields[5]}")
    filesmeta+=("$(printf '%-21s %-30s %-30s' "${fields[1]}" "${fields[4]}" "${fields[5]}")")
    unset fields
  fi
done
unset file

# Print the array contents
#for entry in "${files[@]}"; do
#  echo "$entry"
#done


if [ ${#files[@]} -ge 1 ]
then
        echo "Files: ${#files[@]}"
        PS3="Enter a session number: "
        select entry in ${filesmeta[@]}
        do
                IFS=' ' file+=(${files[$REPLY-1]})
                echo "You selected session ${file[1]} with a size of ${file[0]}."
#               export SFT_GATEWAYS_BETA=true
                sudo $cmd $recpath/${file[1]} |
                        sft session-logs export --insecure --format asciinema --stdin |
                        # Sed is used to set the background by adding this Start line and replacing resets with BG color 100 (bright black).
                        sed --unbuffered 's/}}/}}\n[0.000000001,"o","\\u001b[100m\\r\\nStart\\r\\n\\r\\n"]/g' |
						sed --unbuffered 's/\[00m\|\[0m\|\[m/\[100m/g' |
                        asciinema play -i 2 -s 2 -
						echo -e "\e[00m"
                unset file
        done
else
        echo "No sessions in $recpath"
        exit 1
fi
