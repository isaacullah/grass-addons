#!/bin/sh

# script to build GRASS 8.dev binaries + addons from the `main`
# (c) GPL 2+ Markus Neteler <neteler@osgeo.org>
# 2022
#
# GRASS GIS github, https://github.com/OSGeo/grass
#
###################################################################
# how it works:
# - it updates locally the GRASS source code from github server
# - configures, compiles
# - packages the binaries
# - generated the install scripts
# - generates the programmer's 8 HTML manual
# - generates the pyGRASS 8 HTML manual
# - generates the user 8 HTML manuals
# - injects DuckDuckGo search field

# Preparations, on OSGeo server (neteler@grasslxd):
#  - Install PROJ: http://trac.osgeo.org/proj/ incl Datum shift grids
#     sh conf_proj4.sh
#  - Install GDAL: http://trac.osgeo.org/gdal/wiki/DownloadSource
#     sh conf_gdal.sh
#  - Install apt-get install texlive-latex-extra python3-sphinxcontrib.apidoc
#  - Clone source from github:
#    mkdir -p ~/src ; cd ~/src
#    git clone https://github.com/OSGeo/grass.git main
#  - Prepare target directories:
#    cd /var/www/code_and_data/
#    mkdir grass83
#    cd /var/www/html/
#    ln -s /var/www/code_and_data/grass83 .
#
#################################
PATH=/home/neteler/binaries/bin:/usr/bin:/bin:/usr/X11R6/bin:/usr/local/bin

GMAJOR=8
GMINOR=3
GPATCH="dev"
DOTVERSION=$GMAJOR.$GMINOR
VERSION=$GMAJOR$GMINOR
GVERSION=$GMAJOR

###################
CFLAGSSTRING='-O2'
CFLAGSSTRING='-Werror-implicit-function-declaration -fno-common'
LDFLAGSSTRING='-s'

#define several paths if required:

MAINDIR=/home/neteler
# where to find the GRASS sources (git clone):
SOURCE=$MAINDIR/src/
BRANCH=main
GRASSBUILDDIR=$SOURCE/$BRANCH
TARGETMAIN=/var/www/code_and_data
TARGETDIR=$TARGETMAIN/grass${VERSION}/binary/linux/snapshot
TARGETHTMLDIR=$TARGETMAIN/grass${VERSION}/manuals/

# not built for dev version
## TARGETPROGMAN=$TARGETMAIN/programming${GVERSION}

MYBIN=$MAINDIR/binaries

############################## nothing to change below:

MYMAKE="nice make LD_LIBRARY_PATH=$MYBIN/lib:/usr/lib:/usr/local/lib"

# catch CTRL-C and other breaks:
trap "echo 'user break.' ; exit" 2 3 9 15

halt_on_error()
{
  echo "ERROR: $1"
  exit 1
}

configure_grass()
{

# which package?
#   --with-mysql --with-mysql-includes=/usr/include/mysql --with-mysql-libs=/usr/lib/mysql \

# cleanup
rm -f config_$GMAJOR.$GMINOR.git_log.txt

# reset i18N POT files
git checkout locale/templates/*.pot

CFLAGS=$CFLAGSSTRING LDFLAGS=$LDFLAGSSTRING ./configure \
  --with-cxx \
  --with-sqlite \
  --with-postgres \
  --with-geos \
  --with-odbc \
  --with-cairo --with-cairo-ldflags=-lfontconfig \
  --with-proj-share=/usr/share/proj \
  --with-postgres --with-postgres-includes=/usr/include/postgresql \
  --with-freetype --with-freetype-includes=/usr/include/freetype2 \
  --with-netcdf \
  --with-pdal \
  --with-fftw \
  --with-nls \
  --with-blas --with-blas-includes=/usr/include/atlas/ \
  --with-lapack --with-lapack-includes=/usr/include/atlas/ \
  --with-zstd \
  --with-liblas \
  2>&1 | tee config_$DOTVERSION.git_log.txt

 if [ $? -ne 0 ] ; then
   halt_on_error "configure doesn't work."
 fi
}

######## update from git:

mkdir -p $TARGETDIR
cd $GRASSBUILDDIR/

$MYMAKE distclean > /dev/null 2>&1

# cleanup leftover garbage
git status | grep '.rst' | xargs rm -f
rm -rf lib/python/docs/_build/ lib/python/docs/_templates/layout.html
rm -f config_${DOTVERSION}.git_log.txt ChangeLog

# be sure to be on branch
git checkout $BRANCH

echo "git update..."
git fetch --all --prune && git checkout $BRANCH && git pull --rebase || halt_on_error "git update error!"
git status

# for the contributors list in CMS
cp -f *.csv $TARGETMAIN/uploads/grass/

#configure
echo "configuring"
configure_grass || (echo "$0: an error occurred" ; exit 1)
pwd
ARCH=`cat include/Make/Platform.make | grep ^ARCH | cut -d'=' -f2 | xargs`

########  now GRASS is prepared ####################

#### next compile GRASS:
$MYMAKE


echo "GRASS $VERSION compilation done"

# now GRASS is prepared ############################################

#### create module overview (https://trac.osgeo.org/grass/ticket/1203)
#sh utils/module_synopsis.sh

#### generate developer stuff: pygrass docs + gunittest docs
# generate pyGRASS sphinx manual (in docs/html/libpython/)
# including source code
$MYMAKE sphinxdoclib

##
echo "Copy over the manual + pygrass HTML pages:"
mkdir -p $TARGETHTMLDIR
# don't destroy the addons
\mv $TARGETHTMLDIR/addons /tmp
rm -f $TARGETHTMLDIR/*.*
(cd $TARGETHTMLDIR ; rm -rf barscales colortables icons northarrows)
\mv /tmp/addons $TARGETHTMLDIR

cp -rp dist.$ARCH/docs/html/* $TARGETHTMLDIR/
echo "Copied pygrass progman to http://grass.osgeo.org/grass${VERSION}/manuals/libpython/"

echo "Injecting DuckDuckGo search field into manual main page..."
(cd $TARGETHTMLDIR/ ; sed -i -e "s+</table>+</table><\!\-\- injected in cron_grass8_relbranch_build_binaries.sh \-\-> <center><iframe src=\"https://duckduckgo.com/search.html?site=grass.osgeo.org%26prefill=Search%20manual%20pages%20at%20DuckDuckGo\" style=\"overflow:hidden;margin:0;padding:0;width:410px;height:40px;\" frameborder=\"0\"></iframe></center>+g" index.html)

cp -p AUTHORS CHANGES CITING COPYING GPL.TXT INSTALL REQUIREMENTS.html $TARGETDIR/

# clean wxGUI sphinx manual etc
(cd $GRASSBUILDDIR/ ; $MYMAKE cleansphinx)

############
# generate doxygen programmers's G8 manual
cd $GRASSBUILDDIR/
#$MYMAKE htmldocs-single > /dev/null || (echo "$0 htmldocs-single: an error occurred" ; exit 1)
$MYMAKE htmldocs-single || (echo "$0 htmldocs-single: an error occurred" ; exit 1)

cd $GRASSBUILDDIR/

## clean old TARGETPROGMAN stuff from last run
#if  [ -z "$TARGETPROGMAN" ] ; then
# echo "\$TARGETPROGMAN undefined, error!"
# exit 1
#fi
#mkdir -p $TARGETPROGMAN
#rm -f $TARGETPROGMAN/*.*
#
## copy over doxygen manual
#cp -r html/*  $TARGETPROGMAN/
#
#echo "Copied HTML progman to https://grass.osgeo.org/programming${GVERSION}"
## fix permissions
#chgrp -R grass $TARGETPROGMAN/*
#chmod -R a+r,g+w $TARGETPROGMAN/
#chmod -R a+r,g+w $TARGETPROGMAN/*
## bug in doxygen
#(cd $TARGETPROGMAN/ ; ln -s index.html main.html)

##### copy i18N POT files, needed for https://www.transifex.com/grass-gis/
(cd locale ;
mkdir -p $TARGETDIR/transifex/
cp templates/*.pot $TARGETDIR/transifex/
)

##### generate i18N stats for HTML page path (WebSVN):
## Structure:  grasslibs_ar.po 144 translated messages 326 fuzzy translations 463 untranslated messages.
cd $GRASSBUILDDIR
(cd locale/ ;
touch po/*.po ;
$MYMAKE mo > out.i18n 2>&1 ;
# libs, mods, wx
# hack:
cat out.i18n | tr '\n' ' ' | sed -e 's+ msgfmt+\
msgfmt+g' | tr -s ' ' ' ' | cut -d' ' -f5,6- | sed 's+\,++g' | sed 's+^po/++g' | grep -v 'done for' | sort > $TARGETDIR/i18n_stats.txt
rm -f out.i18n
)

cd $TARGETDIR/
cat i18n_stats.txt | grep mod  > i18n_stats_mods.txt
cat i18n_stats.txt | grep lib  > i18n_stats_libs.txt
cat i18n_stats.txt | grep wxpy > i18n_stats_wxpy.txt
cd $GRASSBUILDDIR

# package the package
$MYMAKE bindist
if [ $? -ne 0 ] ; then
   halt_on_error "make bindist."
fi

#report system:
echo "System:
$ARCH, compiled with:" > grass-$DOTVERSION\_$ARCH\_bin.txt
## echo "Including precompiled $GDALVERSION library for r.in.gdal" >> grass-$DOTVERSION\_$ARCH\_bin.txt
gcc -v 2>&1 | grep -v Reading >> grass-$DOTVERSION\_$ARCH\_bin.txt

# clean old version off
rm -f $TARGETDIR/grass-$DOTVERSION\_$ARCH\_bin.txt
rm -f $TARGETDIR/grass-$DOTVERSION*.tar.gz
rm -f $TARGETDIR/grass-$DOTVERSION*install.sh

############################################
echo "Copy new binary version into web space:"
cp -p grass-$DOTVERSION\_$ARCH\_bin.txt grass-$DOTVERSION*.tar.gz grass-$DOTVERSION*install.sh $TARGETDIR
rm -f grass-$DOTVERSION\_$ARCH\_bin.txt grass-$DOTVERSION*.tar.gz grass-$DOTVERSION*install.sh

# generate manual ZIP package
(cd $TARGETHTMLDIR/.. ; rm -f $TARGETHTMLDIR/*html_manual.zip ; zip -r /tmp/grass-${DOTVERSION}_html_manual.zip manuals/)
mv /tmp/grass-${DOTVERSION}_html_manual.zip $TARGETHTMLDIR/

# error log etc
cp -f config_$DOTVERSION.git_log.txt $TARGETDIR
cp -f error.log $TARGETDIR
chmod -R a+r,g+w $TARGETDIR     2> /dev/null
chmod -R a+r,g+w $TARGETHTMLDIR 2> /dev/null

echo "Written to: $TARGETDIR"

cd $GRASSBUILDDIR

############################################
# compile addons

# update addon repo (addon repo has been cloned twice on the server to
#   separate grass7 and grass8 addon compilation)
(cd ~/src/grass$GMAJOR-addons/; git checkout grass$GMAJOR; git pull origin grass$GMAJOR)
# compile addons
cd $GRASSBUILDDIR
sh ~/cronjobs/compile_addons_git.sh $GMAJOR \
   $GMINOR \
   ~/src/grass$GMAJOR-addons/src/ \
   ~/src/$BRANCH/dist.$ARCH/ \
   ~/.grass$GMAJOR/addons \
   ~/src/$BRANCH/bin.$ARCH/grass \
   1
mkdir -p $TARGETHTMLDIR/addons/
# copy individual addon html files into one target dir if compiled addon
# has own dir e.g. ~/.grass8/addons/db.join/ with bin/ docs/ etc/ scripts/
# subdir
for dir in `find ~/.grass$GMAJOR/addons -maxdepth 1 -type d`; do
    if [ -d $dir/docs/html ] ; then
        if [ "$(ls -A $dir/docs/html/)" ]; then
            for f in $dir/docs/html/*; do
                cp $f $TARGETHTMLDIR/addons/
            done
        fi
    fi
done
sh ~/cronjobs/grass-addons-index.sh $GMAJOR $GMINOR $GPATCH $TARGETHTMLDIR/addons/
cp $TARGETHTMLDIR/grass_logo.png \
   $TARGETHTMLDIR/hamburger_menu.svg \
   $TARGETHTMLDIR/hamburger_menu_close.svg \
   $TARGETHTMLDIR/grassdocs.css \
   $TARGETHTMLDIR/addons/
chmod -R a+r,g+w $TARGETHTMLDIR 2> /dev/null

# cp logs from ~/.grass$GMAJOR/addons/logs/
mkdir -p $TARGETMAIN/addons/grass$GMAJOR/logs/
cp -p ~/.grass$GMAJOR/addons/logs/* $TARGETMAIN/addons/grass$GMAJOR/logs/

# generate addons modules.xml file (required for g.extension module)
~/src/$BRANCH/bin.$ARCH/grass --tmp-location EPSG:4326 --exec ~/cronjobs/build-xml.py --build ~/.grass$GMAJOR/addons
cp ~/.grass$GMAJOR/addons/modules.xml $TARGETMAIN/addons/grass$GMAJOR/modules.xml

# regenerate keywords.html file with addons modules keywords
export ARCH
export ARCH_DISTDIR=$GRASSBUILDDIR/dist.$ARCH
export GISBASE=$ARCH_DISTDIR
export VERSION_NUMBER=$DOTVERSION
python3 $GRASSBUILDDIR/man/build_keywords.py $TARGETMAIN/grass$GMAJOR$GMINOR/manuals/ $TARGETMAIN/grass$GMAJOR$GMINOR/manuals/addons/
unset ARCH ARCH_DISTDIR GISBASE VERSION_NUMBER

############################################
# create sitemaps to expand the hugo sitemap

python3 $HOME/src/grass$GMAJOR-addons/utils/create_manuals_sitemap.py --dir=/var/www/code_and_data/grass$GMAJOR$GMINOR/manuals/ --url=https://grass.osgeo.org/grass$GMAJOR$GMINOR/manuals/ -o
python3 $HOME/src/grass$GMAJOR-addons/utils/create_manuals_sitemap.py --dir=/var/www/code_and_data/grass$GMAJOR$GMINOR/manuals/addons/ --url=https://grass.osgeo.org/grass$GMAJOR$GMINOR/manuals/addons/ -o

############################################
# cleanup
cd $GRASSBUILDDIR
$MYMAKE distclean  > /dev/null || (echo "$0: an error occurred" ; exit 1)
rm -rf lib/html/ lib/latex/

echo "Finished GRASS $VERSION $ARCH compilation."
echo "Written to: $TARGETDIR"
echo "Copied HTML ${GVERSION} manual to https://grass.osgeo.org/grass${VERSION}/manuals/"
echo "Copied pygrass progman ${GVERSION} to https://grass.osgeo.org/grass${VERSION}/manuals/libpython/"
#echo "Copied HTML ${GVERSION} progman to https://grass.osgeo.org/programming${GVERSION}"
echo "Copied Addons ${GVERSION} to https://grass.osgeo.org/grass${VERSION}/manuals/addons/"

exit 0
