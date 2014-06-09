#!/usr/bin/awk -f
# Create: 2014-06-03 John C. Petrucci( http://johncpetrucci.com )
# Modify: 2014-06-04 John C. Petrucci
# Purpose: Portable / easily readable output of Check Point connections table (fw tab -t connections).
# Usage: fw tab -t connections -u | ./awk-connstat.awk
#
function horizontalRule() {
	"tput cols" | getline screenWidth
	for (i = 1; i<= screenWidth; i++) printf "-"
	printf "\n";
}

function ttyCheck() {
	result = ("tty" | getline)
	return result
}

function displayConnections(){
	for (cindex in connectionIndex) {
		for (i = 1; i <= numCols; i++) {
			printf "%17.15s", connections[cindex SUBSEP gensub( / /, "", "g", tolower(cols[i]))];
		}
		printf "\n";
	}
}

function readInput(){
	while (1) {
		printf "%s\t%s\n", "COMMANDS:", "[Q]uit"
		printf "%s", "Enter command: "
		getline REPLY < "/dev/tty"
		if (REPLY ~ /[qQ]/) break
		if (REPLY ~ /[tT]/) summarizeConnections(3) 
		displayHeaders()
		displayConnections()
	}
}

function displayHeaders(){
	cols[1]="SRC IP"
	cols[2]="SRC PORT"
	cols[3]="DST IP"
	cols[4]="DST PORT"
	cols[5]="IPP"
	cols[6]="DIR"
	cols[7]="STATE"
	cols[8]="REMATCH"
	cols[9]="TIMEOUT"
	numCols=9

	connectionColWidths="17,12,17,12,5,6,13,9,9"
	split(connectionColWidths, connectionColWidth, ",")

	for (i = 1; i <= numCols; i++) {
		printf "%"connectionColWidth[i]"s", cols[i];
	}
	printf "\n";
	horizontalRule()
}

function summarizeConnections(topX) {
	horizontalRule()
	# Count total active connections.
	for (i in connectionIndex) totalConnections++
	printf "%15s %'d", "Concurrent:", totalConnections
	if ( connectionsLimit + 1 > 2 ) {
		printf "%15s %'d", "Limit:", connectionsLimit
		if ( totalConnections > ( connectionsLimit * .75) ) printf "%30s", " <-------- WARNING!"
	} else printf "%15s %s", "Limit:", connectionsLimit
	printf "\n"
	horizontalRule() 

	cmdSortSrcip = "sort -nrk3"
	cmdSortDstip = "sort -n -rk3"
	cmdSortDstport = "sort -nr -k3"
	cmdSortState= "sort -n -r -k3"
	# They all have to be slightly different so we can refer to them uniquely for reading and writing.

	for (count in counterSrcip) {
		printf "%s ( %'d )\n", count, counterSrcip[count] |& cmdSortSrcip
	} 
	close(cmdSortSrcip, "to")

	for (count in counterDstip) {
		printf "%s ( %'d )\n", count, counterDstip[count] |& cmdSortDstip
	} 
	close(cmdSortDstip, "to")

	for (count in counterDstport) {
		printf "%s ( %'d )\n", count, counterDstport[count] |& cmdSortDstport
	} 
	close(cmdSortDstport, "to")

	for (count in counterState) {
		printf "%s ( %d%% )\n", count, (counterState[count] / totalConnections) * 100 |& cmdSortState
	} 
	close(cmdSortState, "to")

	# Now paste them all together into parallel columns.
	summaryColWidth = int(strtonum(screenWidth / 5))
	printf "%"summaryColWidth"s %"summaryColWidth"s %"summaryColWidth"s %"summaryColWidth"s\n", "Top Source IPs", "Top Destination IPs", "Top Services", "Connection States" 
	for (i=topX; i>=1; i--) {
		result = (cmdSortSrcip |& getline lineSrcip)
		if (result <= 0) lineSrcip = "---"; else 1 #visualSrcip = substr(
		result = (cmdSortDstip |& getline lineDstip)
		if (result <= 0) lineDstip = "---"
		result = (cmdSortDstport |& getline lineDstport)
		if (result <= 0) lineDstport = "---"
		result = (cmdSortState |& getline lineState)
		if (result <= 0) lineState = "---"

		printf "%"summaryColWidth"s%"summaryColWidth"s%"summaryColWidth"s%"summaryColWidth"s\n", lineSrcip, lineDstip, lineDstport, lineState
	}
	# Close coprocesses
	close(cmdSortSrcip)
	close(cmdSortDstip)
	close(cmdSortDstport)
	close(cmdSortState)

	horizontalRule() 

	# Sort firewall worker / core distribution
	cmdSortCores= "sort -n -r -k2"
	for (core in counterCore) {
		printf "fw_%s: %2d%%\n", core, ((counterCore[core] / totalConnections) * 100) |& cmdSortCores
	}
	close(cmdSortCores, "to")
	
	# Display firewall worker / core distribution
	printf "%"summaryColWidth"s%"summaryColWidth"s%"summaryColWidth"s%"summaryColWidth"s\n", "Worker Distribution", "x", "x", "x" 
	for (core in counterCore) {
		result = (cmdSortCores |& getline lineCore)
		if (result <= 0) lineDstip = "---"
		printf "%"summaryColWidth"s%"summaryColWidth"s%"summaryColWidth"s%"summaryColWidth"s\n", lineCore, "x", "x", "x" 
	}
}

BEGIN {
displayHeaders()
}
$1 ~ /^\[fw_[0-9]+\]/ { # Strip kernel IDs
	if (NF > 15) { # If non-symlink
		core = gensub(/^\[fw_([0-9]+)\].*/, "\\1", "", $0); # Extract and save
		counterCore[core]++ # Increment counter for this core
	}
	$0 = gensub(/^\[fw_[0-9]+\]/, "", "", $0); # Strip and shift
} 
$1 ~ /<0000000(0|1)/ { # Find connections - ignore headers
	if (NF > 15) { # Find non-symlink connections
		connectionIndex[NR] = "1"
		$0 = tolower($0)
		$0 = gensub( /[^0-9a-f \/]/, "", "g", $0 ); # Strip illegal characters
		# Direction
		$1 ~ /00000000/ ? connections[NR, "dir"] = "IN" : connections[NR, "dir"] = "OUT" # Determine direction
		# Source IP
		connections[NR, "srcip"] = \
			strtonum("0x" substr($2, 1, 2))"."\
			strtonum("0x" substr($2, 3, 2))"."\
			strtonum("0x" substr($2, 5, 2))"."\
			strtonum("0x" substr($2, 7, 2))
		counterSrcip[connections[NR, "srcip"]]++
		# Source port
		connections[NR, "srcport"] = strtonum("0x" $3)
		# Destination IP
		connections[NR, "dstip"] = \
			strtonum("0x" substr($4, 1, 2))"."\
			strtonum("0x" substr($4, 3, 2))"."\
			strtonum("0x" substr($4, 5, 2))"."\
			strtonum("0x" substr($4, 7, 2))
		counterDstip[connections[NR, "dstip"]]++
		# Destination port
		connections[NR, "dstport"] = strtonum("0x" $5)
		counterDstport[connections[NR, "dstport"]]++
		# IP protocol
		connections[NR, "ipp"] = strtonum("0x" $6)
		# Connection state
		connections[NR, "state"] = substr($7, 5, 2)
		if (connections[NR, "state"] ~ /^8/) connections[NR, "state"] = "SYN-ACK" # Not sure on the parsing of connections table here.  Need to get clarificaiton / sk65133.
		if (connections[NR, "state"] ~ /1./) connections[NR, "state"] = "SOURCE_FIN"
		if (connections[NR, "state"] ~ /(2|e)./) connections[NR, "state"] = "DEST_FIN" 
		if (connections[NR, "state"] ~ /^(4|c)/) connections[NR, "state"] = "ESTABLISHED" 
		if (connections[NR, "state"] ~ /f./) connections[NR, "state"] = "CLOSED" 
		if (connections[NR, "state"] ~ /00/) connections[NR, "state"] =  "SYN/NONE"
		counterState[connections[NR, "state"]]++
		# Rematch properties
		connections[NR, "rematch"] = substr($8, 6, 1)
		if (connections[NR, "rematch"] >= 8 ) connections[NR, "rematch"] = "NO  " 
		else connections[NR, "rematch"] = "YES  "
		# Timeout
		connections[NR, "timeout"] = sprintf("%'d", strtonum(gensub(/([0-9]+)\/>$/, "\\1", "", $NF)))
		
		# Print this connection
		for (i = 1; i <= numCols; i++) {
			printf "%"connectionColWidth[i]"s", connections[NR, gensub( / /, "", "g", tolower(cols[i]))];
		}
		printf "\n";
	}
}
$1 ~ /^dynamic/ { # Find header
	if ( /unlimited/ ) connectionsLimit = "Automatic"; else connectionsLimit = strtonum(gensub( /.*limit ([0-9]+).*/, "\\1", "", $0))
}

END {
summarizeConnections(10)
}
