#!/usr/bin/env bash -O extglob

stackcollapse-time() {
## Emperically creates a non-linear colorspace mapping (using a screen-space-weighted  CDF) that 
#      ensure that the colorspace is perceptually uniform and has equal spatial distribution.
#
# USAGE:   stackcollapse-time out.folded >out.folded.mod
#          stackcollapse-time <out.folded | flamegraph.pl ( --time | --color=time[p[r]] )
#
# OUTPUT:  for each line in out.folded:
#    a;b;c;d; time [time2] --> a;b;c;d; time:ind [time2:ind2]
#  
#    both "ind" and (if time2 is present) "ind2" are linear maps to the colorspce
#    that range between 0 and 2 * N (N = total number of samples / lines in out.folded)
#
#    this output style is designed to work with `flamegraph.pl --color=time[p[r]]`

    shopt -s extglob

    [[ -f "$1" ]] || {
        printf '\nERROR: no file found at "%s"...ABORTING\n\n' "${1}"
        return 1
    }

    local wallTimeN cpuTimeN wallTimeCDF_csum cpuTimeCDF_csum kk kk0 a b c n cpuTimeFlag
    local -a stackA wallTimeA cpuTimeA wallTimeSortA cpuTimeSortA wallTimeCDF_map0 cpuTimeCDF_map0 wallTimeCDF_map cpuTimeCDF_map

     # seperate logs into stack / wall time / cpu time
    mapfile -t stackA < <(sed -E 's/^(.*)(([[:space:]]+[0-9]+)+)$/\1/' <"${1}") 
    mapfile -t wallTimeA < <(sed -E 's/^(.*)(([[:space:]]+[0-9]+)+)$/\2 /; s/^[[:space:]]+([0-9]+)[[:space:]]+([0-9]*)[[:space:]]*$/\1/' <"${1}") 
    mapfile -t cpuTimeA < <(sed -E 's/^(.*)(([[:space:]]+[0-9]+)+)$/\2 /; s/^[[:space:]]+([0-9]+)[[:space:]]+([0-9]*)[[:space:]]*$/\2/' <"${1}" | grep -E '.+') 

    if (( ${#cpuTimeA[@]} == 0 )); then
        cpuTimeFlag=false
    else
        cpuTimeFlag=true
    fi

    # sort times then prepend line numbers to start
    mapfile -t wallTimeSortA < <( printf '%s\n' "${wallTimeA[@]}" | sort -n | grep -nE '' | sed -E s/'\:'/' '/)
    
    # get total count
    (( wallTimeN = ${#wallTimeSortA[@]} ))
  
    # get unique times and counts and populate inverse mapping arrays
    wallTimeCDF_map0=()
    wallTimeCDF_map=()

    # get map from time -> CDF index and then weight each CDF index by the total time shown at that index
    while read -r a b c; do
        { [[ $a ]] && [[ $b ]] && [[ $c ]]; } || continue
        (( n = ( ( b - 1 ) << 1 ) + a ))
        (( wallTimeCDF_map[$n] = ${wallTimeCDF_map[$n]:-0} + a * c ))
        wallTimeCDF_map0[$c]="$n"
    done < <(printf '%s\n' "${wallTimeSortA[@]}" | uniq -c -f1)

    # cummulative sum weighted CDF to get final "equal screen space" mapping
    kk0=-1
    for n in "${!wallTimeCDF_map[@]}"; do
        (( kk0 >= 0 )) && (( wallTimeCDF_map[$n] = wallTimeCDF_map[$n] + wallTimeCDF_map[$kk0] ))
        kk0=${n}
    done
    wallTimeCDF_csum="${wallTimeCDF_map[$n]}"

    # renormalize final mapping to range between 0 and (2 * numSamples)
    for n in "${!wallTimeCDF_map[@]}"; do
        (( wallTimeCDF_map[$n] = ( ( wallTimeN * wallTimeCDF_map[$n] ) << 1 ) / wallTimeCDF_csum ))
    done

    # if we alsio have cpu times, repeat the above steps to get a weighted CDF mapping for those too
    ${cpuTimeFlag} && {
        mapfile -t cpuTimeSortA < <( printf '%s\n' "${cpuTimeA[@]}" | sort -n | grep -nE '' | sed -E s/'\:'/' '/)

        (( cpuTimeN = ${#cpuTimeSortA[@]} ))

        cpuTimeCDF_map0=()
        cpuTimeCDF_map=()

         while read -r a b c; do
            { [[ $a ]] && [[ $b ]] && [[ $c ]]; } || continue
            (( n = ( ( b - 1 ) << 1 ) + a ))
            (( cpuTimeCDF_map[$n] = ${cpuTimeCDF_map[$n]:-0} + a * c ))
            cpuTimeCDF_map0[$c]="$n"
        done < <(printf '%s\n' "${cpuTimeSortA[@]}" | uniq -c -f1)

        kk0=-1
        for n in "${!cpuTimeCDF_map[@]}"; do
            (( kk0 >= 0 )) && (( cpuTimeCDF_map[$n] = cpuTimeCDF_map[$n] + cpuTimeCDF_map[$kk0] ))
            kk0=${n}
        done
        cpuTimeCDF_csum="${cpuTimeCDF_map[$n]}"

        for n in "${!cpuTimeCDF_map[@]}"; do
            (( cpuTimeCDF_map[$n] = ( ( cpuTimeN * cpuTimeCDF_map[$n] ) << 1 ) / cpuTimeCDF_csum ))
        done
    }

    # re-create log with time(s) mapped to weighted CDF index
    if ${cpuTimeFlag}; then
        for kk in "${!stackA[@]}"; do
            printf '%s\t %s:%s\t %s:%s\n' "${stackA[$kk]}" "${wallTimeA[$kk]}" "${wallTimeCDF_map[${wallTimeCDF_map0[${wallTimeA[$kk]}]}]}" "${cpuTimeA[$kk]}" "${cpuTimeCDF_map[${cpuTimeCDF_map0[${cpuTimeA[$kk]}]}]}" 
        done 
    else
        for kk in "${!stackA[@]}"; do
            printf '%s\t %s:%s\n' "${stackA[$kk]}" "${wallTimeA[$kk]}" "${wallTimeCDF_map[${wallTimeCDF_map0[${wallTimeA[$kk]}]}]}"
        done 
    fi
}

if (( $# == 0 )) && ! [[ -t 0 ]]; then
    # stack traces were passed on stdin
    stackcollapse-time <(cat <&0)
else
    # we were passed file(s) with the stack traces
    until (( $# == 0 )); do
        stackcollapse-time "${1}"
        shift 1
    done
fi
