########################################################################
# Name   : extract_boldchat.bash
# Purpose: Extract data from BoldChat based on report parameters (Report Type, Grouping, From/To Dates, etc.)
#    then parse the JSON output into CSV file
#    The JSON parser requires the open-source JQ, lightweight and flexible command-line JSON processor, 
#    available at https://stedolan.github.io/jq/)
# ===================================================================
#
# CONSTANT values
accountId="12345678901234"
apiSettingId="9876543210998"
apiKey="QvsxzDZCJfGURHOAyhFdsddwqsss2222222Q6m/nesZIZ0a/9qWGGw=="

# Generate epoch value = seconds from Jan-01, 1970 using built-in Unix's date function
# By default, it does not include milliseconds so we add "000". BoldChat API is fine with "000" for milli-seconds
epoch=$(date +"%s")000

# Assemble authentication token and then hash with SHA512
auth="$accountId:$apiSettingId:$epoch"
authHash="$(echo -n "$auth$apiKey" | openssl dgst -sha512 | sed 's/^.* //')"

#=====================================================================
# Report parameters
reportType="0"
grouping="date"

fromDate="2017-06-25"
#fromDate=$(date +%Y-%m-%d -d "yesterday")
fromDateTime=$fromDate"T00:00:00Z"

toDate="2017-08-16"
#toDate=$(date +%Y-%m-%d)
#toDate=$fromDate
toDateTime=$toDate"T23:59:59Z"

delimiter=","

CSVFileName="bc_ChatSummary_$fromDate.csv"

#=====================================================================
# DEBUG section 
echo
echo accountId - $accountId
echo apiSettingId - $apiSettingId
echo epoch - $epoch
echo authHash - $authHash
echo fromDateTime - $fromDateTime
echo toDateTime - $toDateTime
echo
#=====================================================================

# Start report execution in two steps
# 1. runReport to request for a report to run and get the report ID
# 2. getReport to get actual data based on the report ID

#======================================================================
# (1) runReport
base_url="https://api.boldchat.com/aid/$accountId/data/rest/json/v1" 
auth_str="auth=$accountId:$apiSettingId:$epoch:$authHash"

reportID_url="$base_url/runReport?$auth_str&ReportType=$reportType&Grouping=$grouping&FromDate=$fromDateTime&ToDate=$toDateTime"
reportID_json="$(curl $reportID_url)"

# Parse report ID json 
# Expected data in this format {"Data":{"ReportID":"5534921341969801994"},"Status":"success"}
reportIDStatus="$(echo $reportID_json | sed -e 's/^.*"Status"[ ]*:[ ]*"//' -e 's/".*//')"
echo "reportIDStatus = " $reportIDStatus

# If we could not get a "success" in getting the report ID, notify and exit.
if [ $reportIDStatus != "success" ]
then
    echo Failed to get report ID. Send email.
    exit 1
fi

# Get "Success", let's parse for the report ID
reportID="$(echo $reportID_json | sed -e 's/^.*"ReportID"[ ]*:[ ]*"//' -e 's/".*//')"
echo "reportID = " $reportID

#======================================================================
# (2) getReport
#data_url="https://api.boldchat.com/aid/$accountId/data/rest/json/v1/getReport?auth=$accountId:$apiSettingId:$epoch:$authHash&ReportID=$reportID"
data_url="$base_url/getReport?$auth_str&ReportID=$reportID"

count=0
while [  $count -lt 10 ]; do
    # Wait for 10 seconds to ensure the completion of report run
    sleep 10

    # Get report data
    reportData_json="$(curl $data_url)"
    #echo reportData_json - $reportData_json

    # Check for report run status code
    #   0-3 Running
    #   4   Success
    #   5   Timeout
    # REFERENCE: http://help.boldchat.com/help/EN/BoldChat/BoldChat/c_bc_api_reference.html
    dataStatusCode="$(echo $reportData_json | sed -e 's/^.*"StatusCode"://' -e 's/".*//')"
    echo "dataStatusCode ="	$dataStatusCode "(4 = Success)"

    # If Success, break out of the while loop
    if [ $dataStatusCode = "4," ]
    then
        break
    fi
    
    # After 10 loops, let's notify and exit
    if [ $count -eq 10 ]
    then
        echo Failed to get data after threshold. Send email.
        exit 1
    fi

    count=count+1 
    echo "Count = "  $count
done

# JSON output to file called reportData.json
echo $reportData_json > reportData.json

#======================================================================
# Convert JSON to CSV
# Read JSON output file, parse it using JQ and then write to CSV file
#======================================================================
echo
echo Start converting JSON to CSV ...
countRows="$(cat reportData.json | ./jq -r '.Data.Data | length')"
echo "Total # of rows to fetch = " $countRows

# Create column header
echo "\"Start Date\",\"Total Clicks\",\"Unavail\",\"Blocked\",\"Abandon\",\"Unanswer\",\"Answered\",\"AMC\",\"Unanswer Time\",\"ASA\",\"ACT\"" > $CSVFileName

# Parse temporary JSON file and write into the target CSV file
for (( i=0 ; i<=$countRows-1; i++ )); do
	out=""
	for (( j=0 ; j<=10; j++ )); do
		#echo $i $j
		
		param="cat reportData.json | ./jq -r '.Data.Data[$i][$j] | .Value'"
	
		#echo $param
		
		out+="\"$(eval $param)\""
		
		#echo $out
		
		if [ $j -lt 10 ]
		then
			out+=$delimiter
		fi
	done
	echo $out >> $CSVFileName	
done

#======================================================================
# Copy/SFTP to FTP server
# Need to setup security key so no password prompt
#scp $CSVFileName sftpuser@sftphost:/path

#======================================================================
exit 0
