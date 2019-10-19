#!/bin/bash
# This is the cosmosolv version of Sebastian Ehlert (June 2018).
# ------------------------------------------------------------------------
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ------------------------------------------------------------------------
# Hints:
# cosmothermrd reads the temperature from .thermorc, so we need to
# override it for the cosmosolv run. Strange thing might happen if
# you run thermo while doing a cosmosolv run, or run cosmosolv while
# running cosmosolv. So we will write the thermorc for cosmothermrd
# just shortly before we start cosmothermrd and then replace it
# immediately with the old one, but you should be careful, nonetheless.

# ------------------------------------------------------------------------
usage() {
   printf "Usage: cosmosolv [options]\n"
   printf "\n"
   printf "Options:\n"
   printf "\n"
   printf "   -c <prog> use this version of cefine\n"
   printf "   -d <dir>  make COSMO-calculation in this directory\n"
   printf "             cosmotherm is also started in this directory\n"
   printf "   -e <file> write energy_out to <file> for cosmotherm\n"
   printf "   -f        use fine parametrisation (changes SP calculation)\n"
   printf "   -i <file> use <file> as input for cosmotherm\n"
   printf "   -o <file> write cosmo_out to <file> for cosmotherm\n"
   printf "   -s        do necessary single point calculations\n"
   printf "   -t <temp> calculate solvation contribution at <temp> (in K)\n"
   printf "   -h        show this help page\n"
   printf "\n"
   printf "You can provide a .cosmosolvrc to be sourced by this script\n"
   printf "\n"
   printf "Please report bugs to Sebastian Ehlert <ehlert@thch.uni-bonn.de>\n"
}

# ------------------------------------------------------------------------
# set defaults
cosmothermrd=cosmothermrd
energy_out=out.energy
cosmo_out=out.cosmo
calc_dir=COSMO
input_file=~/.cosmothermrc
scf=false
use_fine=false
temp=298.15
cefine=my_cefine
BP86defTZVP='-bas def-TZVP -grid m3 -novdw -func b-p -sym c1 -noopt'
BP86def2TZVPD='-bas def2-TZVPD -grid m3 -novdw -func b-p -sym c1 -noopt'
workdir=$PWD

# ------------------------------------------------------------------------
# if a cosmosolvrc is present, source it right before reading the commandline
if [ -f ~/.cosmosolvrc ]
then
   . ~/.cosmosolvrc
fi

# ------------------------------------------------------------------------
# read commandline arguments
while getopts i:st:c:fo:d:h opt; do
   case "${opt}" in
   i)
      input_file=${OPTARG}
      ;;
   s)
      scf=true
      ;;
   t)
      temp=${OPTARG}
      ;;
   c)
      cefine=${OPTARG}
      ;;
   f)
      use_fine=true
      ;;
   e)
      energy_out=${OPTARG}
      ;;
   o)
      cosmo_out=${OPTARG}
      ;;
   d)
      calc_dir=${OPTARG}
      ;;
   h)
      usage
      1>&2 printf "normal termination of cosmosolv\n"
      exit 2
      ;;
   *)
      usage
      1>&2 printf "abnormal termination of cosmosolv\n"
      exit 1
      ;;
   esac
done


# ------------------------------------------------------------------------
# calculation starts here
if $scf
then
   printf "------------------------------> BP86/def-TZVP SP\n"
   if [ -d ${calc_dir} ]
   then
      if [ ${calc_dir} == ${HOME} ]
      then
         printf "Please... think first next time... or you will regret it.\n"
         1>&2 printf "security shutdown of cosmosolv\n"
         exit 42
      else
         rm -r ${calc_dir}
      fi
   fi
   mkdir ${calc_dir}

   if [ -f coord ]
   then
      cp coord ${calc_dir}
   else
      printf "did not find a coord file here, please provide one\n"
      1>&2 printf "abnormal termination of cosmosolv\n"
      exit 1
   fi
   if [ -f .UHF ]
   then
      cp .UHF ${calc_dir}
   fi
   if [ -f .CHRG ]
   then
      cp .CHRG ${calc_dir}
   fi

   cd ${calc_dir}

   if $use_fine
   then
      $cefine $BP86def2TZVPD
   else
      $cefine $BP86defTZVP
   fi

   kdg cosmo
   if $use_fine
   then
      printf "running BP86/def2-TZVPD SP 1 ... "
   else
      printf "running BP86/def-TZVP SP 1 ... "
   fi
   ridft > scf1.out 2> scf1.err
   printf "[done]\n"
   actual -r | tee -a scf1.err
   # get gas phase energies
   tail -2 energy | head -1 | gawk '{print $2}' > ${energy_out}

   # prepare cosmo calculation
   kdg end
   printf "\$cosmo\n" >> control
   printf " epsilon=infinity\n" >> control
   if $use_fine
   then
      printf " use_contcav\n" >> control
      printf " cavity closed\n" >> control
      printf "\$cosmo_isorad\n" >> control
   fi
   printf "\$cosmo_out file=${cosmo_out}\n" >> control
   printf "\$end\n" >> control
   if $use_fine
   then
      printf "running BP86/def2-TZVPD SP 2 ... "
   else
      printf "running BP86/def-TZVP SP 2 ... "
   fi
   ridft > scf2.out 2> scf2.err
   printf "[done]\n"
   actual -r | tee -a scf2.err

   cd $workdir
fi

# ------------------------------------------------------------------------
# read the results
if [ -d ${calc_dir} ]
then
   cd ${calc_dir}
   # input file, make a copy just to be sure it does not change
   cp $input_file cosmotherm.inp
   # run
   printf "running COSMOTHERM ... "
   cosmotherm cosmotherm.inp
   printf "[done]\n"
   # list of G(T)
   #grep 'T =' cosmotherm.tab | gawk '{print $8}' > cosmotherm.dat
   #grep 'T=' cosmotherm.tab | gawk '{print $6}' > cosmotherm.dat          # New version X16
   # the -oP way
   printf "find temperatures from ${input_file} in cosmotherm.tab\n"
   grep -oP 'T\s?=\s+\d+\.\d+' cosmotherm.tab | awk '{print $NF}' \
     > cosmotherm.dat
   printf "\n" >> cosmotherm.dat
   printf "find results from cosmotherm run in cosmotherm.tab\n"
   grep ' out ' cosmotherm.tab | gawk '{print $NF}' >> cosmotherm.dat
   printf "compute Hsolv from Gsolv(T) and write .HSOLV and .GSOLV\n"

   # save the old thermorc and write temperature to it
   save_thermo=$(cat ~/.thermorc)
   printf "50.0 ${temp} 1.0" > ~/.thermorc
   $cosmothermrd < cosmotherm.dat
   # restore thermorc as quick as possible
   printf "${save_thermo}\n" > ~/.thermorc

   #eiger -g | grep Gap
   if [ -f .HSOLV ]
   then
      cp .HSOLV $workdir
   fi
   if [ -f .GSOLV ]
   then
      cp .GSOLV $workdir
      cp .GSOLV $workdir/.G$temp
   fi
   if [ -f .VWORK ]
   then
      cp .VWORK $workdir
   fi

   cd $workdir
else
   printf "COSMO-directory: '${calc_dir}' not found\n"
   1>&2 printf "abnormal termination of cosmosolv\n"
   exit 1
fi

1>&2 printf "normal termination of cosmosolv\n"
exit 0
