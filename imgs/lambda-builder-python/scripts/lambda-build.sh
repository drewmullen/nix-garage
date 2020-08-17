#!/bin/env bash


######
#
# Script will build a .zip file that contains ruby or python files
# in the passed directory. Make sure that the .python-version or
# .ruby-version files exist in the lambda root.
#
# It can also push up that .zip to S3 and provide you with the
# S3 Object ID that can be fed into terraform.
#
######
set -e
set -x

create_zip_python(){
  if [ -d ${BUILDDIR} ]; then
    echo "Build directory already exists"
    exit 1
  else
    mkdir $BUILDDIR
  fi
  if [ -f ${PROJECTDIR}/setup.py ]; then
    python -m venv ${PROJECTDIR}/${BUILDDIR}/virtualenv
    ${BUILDDIR}/virtualenv/bin/python ${PROJECTDIR}/setup.py install
    # creating an SDIST is the pythonic way to build your module code package
    # unfortunately, sdist does not allow you to specify the output file name
    # we do some zip drudgery simply to match the sdist package to the needs of lambda
    ${PROJECTDIR}/${BUILDDIR}/virtualenv/bin/python ${PROJECTDIR}/setup.py sdist --formats=zip --dist-dir ${PROJECTDIR}/${BUILDDIR}
    DISTNAME=$(basename $(find ${PROJECTDIR}/${BUILDDIR}/ -type f -iname "$LAMBDANAME*.zip") | rev | cut -d. -f 2- | rev)
    unzip -d ${PROJECTDIR}/${BUILDDIR}/ ${PROJECTDIR}/${BUILDDIR}/${DISTNAME}.zip
    # https://github.com/pypa/setuptools/issues/2325
    # L35 should not be required but is a workaround due to issue on L33
    zip -q9 ${PROJECTDIR}/${BUILDDIR}/${LAMBDANAME}.zip *.py
    pushd ${PROJECTDIR}/${BUILDDIR}/${DISTNAME}/
    # create zip to publish to s3
    zip -qr9 ${PROJECTDIR}/${BUILDDIR}/${LAMBDANAME}.zip .
    popd

    # zip dependencies
    pushd ${BUILDDIR}/virtualenv/lib/python*/site-packages/
    zip -qr9 ${PROJECTDIR}/${BUILDDIR}/${LAMBDANAME}.zip .
    popd

  elif [ -f ${PROJECTDIR}/requirements.txt ]; then
    zip -q9 ${BUILDDIR}/${LAMBDANAME}.zip *.py
    python -m venv ${BUILDDIR}/virtualenv
    ${BUILDDIR}/virtualenv/bin/python ${PROJECTDIR}/setup.py install
    pushd ${BUILDDIR}/virtualenv/lib/python*/site-packages/
    zip -qr9 ${PROJECTDIR}/${BUILDDIR}/${LAMBDANAME}.zip .
    popd
  else
    exit "You must include either requirements.txt or setup.py. Exiting."
  fi
}

create_zip_ruby(){
  if [ -d ${BUILDDIR} ]; then
    echo "Build directory already exists"
    exit 1
  else
    mkdir $BUILDDIR
  fi
  bundle install --deployment
  zip -qr9 ${BUILDDIR}/${LAMBDANAME}.zip *.rb vendor
}

create_zip(){
  lang=$(find . -maxdepth 1 -iname '*-version' -printf '%f\n' | sed  's/^.\(.*\)-version/\1/')
  if [ "$lang" == "python" ];then
    create_zip_python
  elif [ "$lang" == "ruby" ];then
    create_zip_ruby
  else
    echo "Can identify the language, found: $lang"
    exit 1
  fi
}

publish_to_s3(){
  ${AWSCLI} s3 cp ${BUILDDIR}/${LAMBDANAME}.zip \
            s3://${BUCKET}/${BUCKET_PREFIX}/
  object_version=$(${AWSCLI} s3api list-object-versions \
                             --bucket ${BUCKET} \
                             --prefix ${BUCKET_PREFIX}/${LAMBDANAME}.zip \
                             --query 'Versions[?IsLatest==`true`].VersionId' \
                             --output text)
  echo "The S3 object ID is: ${object_version}"
  OUTPUT+="%0A%0A${BUCKET}/${BUCKET_PREFIX}/${LAMBDANAME}: ${object_version}"
}

cleanup(){
  rm -rf $BUILDDIR
}

find_awscli(){
  set +e nounset
  AWSCLI=$(which aws)
  if [ "$?" -ne "0" ]; then
    echo "Can't find awscli"
    exit 1
  fi
  set -e nounset
}


usage(){
  cat << EOF
usage: $(basename $0) [OPTIONS] ARGS

Package and publish lambda code. Uses AWS credentials from AWS_* vars. Can accept multiple buckets.

OPTIONS:
  -h      Show this message
  -k      Set bucket prefix key
  -y      Dont prompt for changes to be pushed

EXAMPLES:
  Build lambda and push to test-bucket:

      $(basename $0) build code/directory/ test-bucket

EOF
}

#####
#
# Main
#
#####

# Defaults
NOPROMPT=0
BUCKET_PREFIX='lambda'

while getopts "hk:y" OPTION
do
  case $OPTION in
    h )
      usage
      exit 0
      ;;
    y )
      NOPROMPT=1
      ;;
    k )
      BUCKETPREFIX=$OPTARG
      ;;
    \? )
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

if [ "$#" -lt 3 ]; then
   echo "ERROR: Missing required arguments"
   echo "ARGS: " $@
   usage
   exit 1
fi

ACTION=$1
PROJECTDIR=$(realpath $2)
BUCKETS=${@:3}
BUILDDIR=".build"
LAMBDANAME=$(basename "${PROJECTDIR}")
#VIRTUALENV=$(which virtualenv)
ZIPBIN=$(which zip)
AWSCLI=''
OUTPUT='Published new versions to S3:'

# Make sure were in the write dir
pushd ${PROJECTDIR}
if [ $ACTION == 'build' ];then
  find_awscli
  create_zip
  for BUCKET in $BUCKETS
  do
    if [ $NOPROMPT == 1 ];then
      publish_to_s3
    else
      read -r -p "Publish to s3://${BUCKET}/${BUCKET_PREFIX}/? [y/N] " response
      case $response in
          [yY][eE][sS]|[yY])
            publish_to_s3
            ;;
      esac
    fi
  done
  # sets an ouput that can be used by github actions
  echo "::set-output name=output::$OUTPUT"
elif [ $ACTION == 'clean' ];then
  cleanup
else
  echo 'Argument not understood or missing'
fi
popd

