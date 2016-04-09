#!/bin/bash
# This script aims to produce gnuplot output to display dhus users 
# accesses graph of frequency and average response time per minutes 
# or seconds.
# The gnuplot configuration writes a png file with format 2000x800.
#
# Be sure the log file start and ends  with a regular log format:
# [X.X.X][2016-02-21 23:59:34,732][INFO ] blablabla...
#
# parameters:
# plot_access_frequency.sh <log_file> [max number of occurence to match]
# "max number of occurence to match" is the limit of occurence to be retained 
#   starting from the end of the logs. The end to have the most recent
#   frequencies.
# sample of usage:
# $> plot_access_frequency.sh dhus.log 5000 | gnuplot

# This must be execute with bash!!!
if [ ! "$BASH_VERSION" ] ; then
    exec /bin/bash "$0" "$@"
fi

# Setup timzone : gnuplot is always UTC the gap between local and UTC must 
# be computed.
LOCAL=$(date +"%Y-%m-%d %H:%M:%S %Z")
UTC=$(date -u -d "$LOCAL" +"%Y-%m-%d %H:%M:%S")  #remove timezone reference
UTCSECONDS=$(date -d"$UTC" +%s)
LOCALSECONDS=$(date -d"$LOCAL" +%s)        
TIMEZONEGAP=$(($LOCALSECONDS-$UTCSECONDS))

log_file=$1
limit=${2:-"20000"}
SCALE=60 # SCALE: The time scale factor: 
         #     1 means count accesses per seconds, 
         #    60 means gather accesses per minutes.
         # not tested 3600 gather access per hour ...

OCCURENCE_TO_FIND=" Access "

# Build the dates
start=$(cat $log_file | head -n 1|cut -d[ -f3 | cut -d] -f1)
stop=$(cat $log_file | tail -n 1|cut -d[ -f3 | cut -d] -f1)
start_s=$(date +%s -d"${start}")
stop_s=$(date +%s -d"${stop}")
start_string=$(date +'%Y-%m-%d %H:%M:%S' -d"${start}")
stop_string=$(date +'%Y-%m-%d %H:%M:%S' -d"${stop}")

# Grep to produce list of records according to the occurences to find.
# Dates are converted to minutes instead of second to reduce the 
# number of records. 
accesses=$(cat $log_file | 
   grep "${OCCURENCE_TO_FIND}" | 
   tail -n $limit | 
   cut -d[ -f3 | cut -d] -f1 | 
   xargs -I {} date +%s -d{} | 
   xargs -I {} echo "scale=0; ({}/${SCALE})"  | bc -l)
IFS=$'\n' access_time=$(sort -n -u <<< "${accesses[*]}" )

## Output the gnuplot command
plotfile=$(echo $log_file| rev | cut -d. -f2 | rev)
cat << EOI
set terminal png size 2000,800
set title "Frequency of \"${OCCURENCE_TO_FIND}\"\nsince $start_string to $stop_string"
set output '$plotfile-frequency.png'

set xlabel  "Date/Time"
set ylabel  "Number of accesses per minutes"
set y2label "Average time(ms)

set xtics rotate by -45 font ",8"

set xdata time
set timefmt "%s"
set format x "%d-%m-%Y %H:%M:%S"

set ytics nomirror
set ytics textcolor rgb "green"
set y2tics textcolor rgb "red"
set y2tics
set tics out
set y2range [0:]
set yrange [0:]

set boxwidth 0.80 relative
set style fill transparent solid 0.5 
plot "-" using (\$1 + $TIMEZONEGAP):2 title 'Number of accesses per minutes' with boxes lc rgb 'green',  \
     "-" using (\$1 + $TIMEZONEGAP):3 title 'Response Time Average(ms)'  with lines axes x1y2 lc rgb 'red'
EOI

# Compute time spent in requests per minutes
time_spent=$(
   count=0
   list_date_delay=$(cat $log_file | 
      grep "${OCCURENCE_TO_FIND}" | 
      tail -n $limit | 
      sed -e 's/^\[[^]]*\]\[\([^]]*\)\]\[[^]]*\] [^[]* \[\([^["ms"]*\)ms\].*$/\1  \2/' | 
      grep -v '^\[.*$' | tr -s '[:blank:]')

   while read -e spent
   do
      date=$(cut -d' ' -f1-2 <<< "${spent}")
      proc_time=$(cut -d' ' -f3 <<< "${spent}")
      date_mn=$(($(date +"%s" -d"$date")/${SCALE}))
      if [ ${date_mn} != "${previous_date_mn}" ] &&
         [ ! -z "${previous_date_mn}" ]; then
         if [ -z "$count" ] || [ "$count" == "0" ]; then
            echo "$previous_date_mn 0"
         else
            echo "$previous_date_mn $(echo "scale=3; $cumul_proc/$count" | bc -l)"
         fi
         cumul_proc=0
         count=0
      else
         cumul_proc=$(echo "${cumul_proc:-0}+$proc_time" | bc -l)
         count=$(($count+1))
      fi
      previous_date_mn=$date_mn
   done <<< "${list_date_delay}"
   echo "$previous_date_mn $(echo "scale=3; $cumul_proc/$count" | bc -l)"
)

# Generate the plot data
echo "# Time,	count,	delay"
table=$(
   for time in $access_time
   do
      count=$(grep "^${time}$" <<< "$accesses[*]" | wc -l)
      if [ "$count" ] && [ "$time" ]  ; then
         delay=$(grep "^${time}" <<< "${time_spent}" | cut -d' ' -f2)
         echo "$(($time*${SCALE})), $count, $delay"
      fi
   done
   echo "end"
)

cat <<< "${table}"
cat <<< "${table}"
