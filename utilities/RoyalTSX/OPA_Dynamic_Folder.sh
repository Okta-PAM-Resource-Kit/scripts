# RoyalTSX automatically prepends script interpreter specific shebang, including one would generate a warning
# No warranty!
# shad.lutz@okta.com

 
# Get this out of the way so it doesn't mess with the JSON output.
sft login >/dev/null
 
OLDIFS=$IFS
 
echo '{"Objects": [ { "Type": "Credential", "Name": "OPA-Placeholder-User", "Username": "Unused", "Password": "unusedpassword", "ID": "000001", "Path": "/zUnusedSshCredentials" },'
 
    unset lasthostcreated
    IFS=$'\n'
    for hostline in `sft list-servers --columns hostname,os_type | grep -v HOSTNAME | sort`; do
        IFS=$OLDIFS read hostname os_type <<< $hostline
        if [ ! -z "$lasthostcreated" ]; then
            echo ','
        fi
        
        if [ $os_type = linux ]; then
            echo '{ "Type": "TerminalConnection",
            "TerminalConnectionType": "SSH",
            "Name": "'$hostname'",
            "ComputerName": "'$hostname'",
            "CredentialID": "000001" }'
        elif [ $os_type = windows ]; then
            echo '{ "Type": "CommandTask",
            "CommandMac": "sft",
            "NoConfirmationRequired": "true",
            "ExecuteInTerminalOSX": "false",
            "IconName": "Flat/Hardware/Platform OS Windows",
            "ArgumentsMac": "rdp '$hostname'",
            "Name": "'$hostname'" }'
        fi
        lasthostcreated=$hostname
    done
    IFS=$OLDIFS

# Close objects
echo ']}'