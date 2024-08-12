#!/bin/bash

trap "exit 1" TERM
# Check for required commands
for cmd in curl openssl python; do
    if ! command -v $cmd >/dev/null 2>&1; then
        stdError "$cmd command is required but not installed."
        exit 1
    fi
done
TEMP_DIR="./temp"
LOGS_DIR="./logs"
LINKSFILE="links.txt"

# Create directories if they do not exist
mkdir -p "$TEMP_DIR"
mkdir -p "$LOGS_DIR"

# Generate a unique output filename based on the current date and time
timestamp=$(date '+log_D_%d_%m_%Y_T_%H_%M_%S')
OUTPUTFILE="${LOGS_DIR}/${timestamp}.txt"
ANALYSISFILE="${LOGS_DIR}/analysis_${timestamp}.txt"
>"$OUTPUTFILE"   # cleans the output file content
>"$ANALYSISFILE" # cleans the analysis file content
# Initialize the Excel file
python auto.py initialize

if ! test -f "$LINKSFILE"; then
    echo "Missing required file: links.txt" >>"$OUTPUTFILE"
    exit 1
fi

function stdOutput {
    if ! test "$SILENT" = true; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$OUTPUTFILE"
    fi
}

function stdError {
    if ! test "$SILENT" = true; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: $1" >>"$OUTPUTFILE"
    fi
}

function stdAnalysis {
    if ! test "$SILENT" = true; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$ANALYSISFILE"
    fi
}

# Use curl to check internet connectivity
if ! curl -s --head http://www.google.com | grep "200 OK" >/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Internet connectivity not available" >>"$OUTPUTFILE"
    exit 1
fi

# Loop through each line in links.txt
declare -i Count=0
declare -i Http200Count=0
declare -i Http302Count=0
declare -i Http307Count=0
declare -i Http503Count=0
declare -i HttpOtherCount=0
declare -i Curl6Count=0
declare -i Curl28Count=0
declare -i Curl35Count=0
declare -i Curl60Count=0
declare -i CurlOtherCount=0
declare -i SslCount=0
declare -i SslActiveCount=0
declare -i SslExpiredCount=0
declare -i NoSslCount=0
declare -i SslToRenewCount=0
declare -i SslFetchErrorCount=0

while IFS= read -r WEBPAGE || [[ -n "$WEBPAGE" ]]; do
    # Skip empty lines and comments starting with #
    if [[ "$WEBPAGE" =~ ^[[:space:]]*$ || "$WEBPAGE" =~ ^# ]]; then
        continue
    fi

    # Trim leading/trailing whitespace (if any)
    WEBPAGE=$(echo "$WEBPAGE" | xargs)
    ((Count++))
    stdOutput "$Count"

    # Check website HTTP status
    HTTPCODE=$(curl --max-time 30 --write-out "%{http_code}" --output /dev/null "$WEBPAGE")
    CURL_EXIT_CODE=$?

    # Determine the status
    REDIRECT="N/A"
    case $HTTPCODE in
    200)
        stdOutput "HTTP STATUS CODE $HTTPCODE -> $WEBPAGE is OK"
        STATUS="OK"
        ((Http200Count++))
        ;;
    302)
        stdOutput "HTTP STATUS CODE $HTTPCODE -> $WEBPAGE is OK (302)"
        STATUS="OK"
        REDIRECT="302"
        ((Http302Count++))
        ;;
    307)
        stdOutput "HTTP STATUS CODE $HTTPCODE -> $WEBPAGE is OK (307)"
        STATUS="OK"
        REDIRECT="307"
        ((Http307Count++))
        ;;
    503)
        stdError "HTTP STATUS CODE $HTTPCODE -> $WEBPAGE in Maintenance"
        STATUS="Maintenance"
        ((Http503Count++))
        ;;
    *)
        stdError "HTTP STATUS CODE $HTTPCODE -> $WEBPAGE is down or has issues"
        STATUS="Down or Issues"
        ((HttpOtherCount++))
        ;;
    esac

    # Check website SSL
    if echo "$WEBPAGE" | grep -iq "https"; then
        SSL_EXPIRE=$(
            openssl s_client -connect $(echo "$WEBPAGE" |
                sed -e 's!https://!!' |
                cut -d/ -f1):443 -servername $(echo "$WEBPAGE" |
                    sed -e 's!https://!!' |
                    cut -d/ -f1) </dev/null 2>/dev/null |
                openssl x509 -noout -dates 2>/dev/null |
                grep 'notAfter=' |
                cut -d= -f2
        )

        if [ $? -ne 0 ]; then
            stdError "Failed to fetch SSL certificate for $WEBPAGE"
            SSL_STATUS="Fetch Error"
            DAYS_UNTIL_EXPIRATION="N/A"
            ((SslFetchErrorCount++))
        else
            if [ -n "$SSL_EXPIRE" ]; then
                EXPIRE_DATE=$(date -d "$SSL_EXPIRE" "+%s" 2>/dev/null)
                if [ $? -ne 0 ]; then
                    stdError "Error parsing SSL expiration date for $WEBPAGE"
                    SSL_STATUS="Fetch Error"
                    DAYS_UNTIL_EXPIRATION="N/A"
                    ((SslFetchErrorCount++))
                else
                    CURRENT_DATE=$(date "+%s")
                    DAYS=$((($EXPIRE_DATE - $CURRENT_DATE) / (60 * 60 * 24)))

                    if test $DAYS -gt 7; then
                        SSL_STATUS="Active"
                        stdOutput "No need to renew the SSL certificate. It will expire in $DAYS days."
                        ((SslActiveCount++))
                    elif test $DAYS -gt 0; then
                        SSL_STATUS="To Renew"
                        stdOutput "The SSL certificate should be renewed as soon as possible ($DAYS remaining days)."
                        ((SslToRenewCount++))
                        ((SslActiveCount++))
                    else
                        SSL_STATUS="Expired"
                        stdError "The SSL certificate IS ALREADY EXPIRED!"
                        ((SslExpiredCount++))
                    fi
                    ((SslCount++))
                    DAYS_UNTIL_EXPIRATION=$DAYS
                fi
            else
                SSL_STATUS="Fetch Error"
                stdError "Could not retrieve SSL certificate details."
                DAYS_UNTIL_EXPIRATION="N/A"
                ((SslFetchErrorCount++))
            fi
        fi
    else
        SSL_STATUS="Not Secured"
        stdError "No SSL found"
        DAYS_UNTIL_EXPIRATION="N/A"
        ((NoSslCount++))
    fi

    # Log the curl error
    if [ $CURL_EXIT_CODE -ne 0 ]; then
        case $CURL_EXIT_CODE in
        6)
            stdError "curl error $CURL_EXIT_CODE (Couldn't resolve host)"
            ((Curl6Count++))
            ;;
        28)
            stdError "curl error $CURL_EXIT_CODE (Operation timed out)"
            ((Curl28Count++))
            ;;
        35)
            stdError "curl error $CURL_EXIT_CODE (SSL connect error)"
            ((Curl35Count++))
            ;;
        60)
            stdError "curl error $CURL_EXIT_CODE (SSL certificate problem)"
            ((Curl60Count++))
            ;;
        *)
            stdError "curl error $CURL_EXIT_CODE"
            ((CurlOtherCount++))
            ;;
        esac
    fi

    # Call Python script to append data to Excel
    python auto.py "$WEBPAGE" "$STATUS" "$SSL_STATUS" "$DAYS_UNTIL_EXPIRATION" "$REDIRECT"

    stdOutput "|"
done <"$LINKSFILE"

# Write overall analysis summary to ANALYSISFILE
stdAnalysis "HTTP Status Codes"
stdAnalysis "(Count: $((Http200Count + Http302Count + Http307Count + Http503Count + HttpOtherCount)))"
stdAnalysis "================="
stdAnalysis "OK : $Http200Count"
stdAnalysis "OK but Redirected (302) : $Http302Count"
stdAnalysis "OK but Redirected Temporary (307) : $Http307Count"
stdAnalysis "Maintenance : $Http503Count"
stdAnalysis "Failed/Other issues : $HttpOtherCount"
stdAnalysis "|"
stdAnalysis "Curl Errors"
stdAnalysis "==========="
stdAnalysis "Couldn't resolve host : $Curl6Count"
stdAnalysis "Operation timed out : $Curl28Count"
stdAnalysis "SSL connect error: $Curl35Count"
stdAnalysis "SSL certificate problem : $Curl60Count"
stdAnalysis "Other issues : $CurlOtherCount"
stdAnalysis "|"
stdAnalysis "|"
stdAnalysis "SSL Status"
stdAnalysis "=========="
stdAnalysis "SSL enabled : $SslCount"
stdAnalysis "No SSL : $NoSslCount"
stdAnalysis "|"
stdAnalysis "SSL Detail"
stdAnalysis "=========="
stdAnalysis "SSL active : $SslActiveCount"
stdAnalysis "SSL certificates to renew : $SslToRenewCount"
stdAnalysis "Expired SSL certificates : $SslExpiredCount"
stdAnalysis "SSL fetch errors : $SslFetchErrorCount"
stdAnalysis "|"

echo "Script execution completed. Check $OUTPUTFILE and $ANALYSISFILE for details."
