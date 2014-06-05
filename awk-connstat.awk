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

function displayConnections(){
	for (cindex in connectionIndex) {
		for (i = 1; i <= numCols; i++) {
			printf "%17.15s", connections[cindex SUBSEP gensub( / /, "", "g", tolower(cols[i]))];
		}
		printf "\n";
	}
	horizontalRule()
}

function readInput(){
	while (1) {
		printf "%s", "Enter command: "
		getline REPLY < "/dev/tty"
		if (REPLY ~ /[qQ]/) break
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
	numCols=7

	for (i = 1; i <= numCols; i++) {
		printf "%17.15s", cols[i];
	}
	printf "\n";
	horizontalRule()
}

BEGIN {
displayHeaders()
}

$1 ~ /<0000000(0|1)/ { # Find connections - ignore headers
	if (NF > 15) { # Find non-symlink connections
		connectionIndex[NR] = "1"
		$0 = tolower($0)
		$0 = gensub( /[^0-9a-f ]/, "", "g", $0 ); # Strip illegal characters
		# Direction
		$1 ~ /00000000/ ? connections[NR, "dir"] = "IN" : connections[NR, "dir"] = "OUT" # Determine direction
		# Source IP
		connections[NR, "srcip"] = \
			strtonum("0x" substr($2, 1, 2))"."\
			strtonum("0x" substr($2, 3, 2))"."\
			strtonum("0x" substr($2, 5, 2))"."\
			strtonum("0x" substr($2, 7, 2))
		# Source port
		connections[NR, "srcport"] = strtonum("0x" $3)
		# Destination IP
		connections[NR, "dstip"] = \
			strtonum("0x" substr($4, 1, 2))"."\
			strtonum("0x" substr($4, 3, 2))"."\
			strtonum("0x" substr($4, 5, 2))"."\
			strtonum("0x" substr($4, 7, 2))
		# Destination port
		connections[NR, "dstport"] = strtonum("0x" $5)
		# IP protocol
		connections[NR, "ipp"] = strtonum("0x" $6)
		# Connection state
		connections[NR, "state"] = substr($7, 5, 2)
		if (connections[NR, "state"] ~ /c/) connections[NR, "state"] = "ESTABLISHED" # Not sure on the parsing of connections table here.  Need to get clarificaiton / sk65133.
		else connections[NR, "state"] = "SYN_SENT"
	}
}

END {
displayConnections()
readInput()
}
