#!/usr/bin/env bash

# A Docker image is a combination of REGISTRY/NAMESPACE/REPOSITORY[:TAG].
# Registry will be ignored for now unless we move off Docker Hub.

# Import repo-specific image information
source ./manifest
tagless_image=cimg/${repository}

# prepare file
echo "#!/usr/bin/env bash" > ./build-images.sh
echo "" >> ./build-images.sh

# A version can be a major.minor or major.minor.patch version string.
# An alias can be passed right after the version with an equal sign (=).
# An additional parameter can be passed with a hash (#) sign.
# Additionally versions/version groups are separated by spaces.
#
# Examples:
#
# 1.13.1 v1.14.2
# v1.13.1#sha256abcfabdbc674bcg
# v13.0.1=lts
# v20.04
# v8.0.252=lts=https://example.com/download/item.tar-gz

#####
# Starting version loop. 
#####
for versionGroup in "$@"; do
	# Process the version group(s) that were passed to this script.
	if [[ "$versionGroup" == *"#"* ]]; then
		vgParam1=$(cut -d "#" -f2- <<< "$versionGroup")
		versionGroup="${versionGroup//$vgParam1}"
		versionGroup="${versionGroup//\#}"
	fi

	if [[ "$versionGroup" == *"="* ]]; then
		vgAlias1=$(cut -d "=" -f2- <<< "$versionGroup")
		versionGroup="${versionGroup//$vgAlias1}"
		versionGroup="${versionGroup//=}"
	fi
	# Checks for the current LTS version and compares to passed in version to prevent backtracking
	# Not sure if this should be going into gen or release - this technically makes it more general
	if [[ $vgAlias1 ]]; then
		currentLTS="$(grep 'lts' ALIASES | cut -d "=" -f2)"
		if [ "$(printf '%s\n' "$versionGroup" "$currentLTS" | sort -V | head -n1)" = "$versionGroup" ]; then
			echo "Please use an updated LTS version" 
			exit 1
		fi
	fi

	vgVersion=$(cut -d "v" -f2- <<< "$versionGroup")

	string="docker build"

	if [[ $vgVersion =~ ^[0-9]+\.[0-9]+ ]]; then
		versionShort=${BASH_REMATCH[0]}
	else
		echo "Version matching failed." >&2
		# continue
	fi

	[[ -d "$versionShort" ]] || mkdir "$versionShort"

	sed -e 's!%%PARENT%%!'"$parent"'!g' "./Dockerfile.template" > "./$versionShort/Dockerfile"
	sed -i.bak 's/%%MAIN_VERSION%%/'"${vgVersion}"'/g' "./${versionShort}/Dockerfile"  # will be deprecated in the future
	sed -i.bak 's/%%VERSION_FULL%%/'"${vgVersion}"'/g' "./${versionShort}/Dockerfile"
	sed -i.bak 's/%%VERSION_MINOR%%/'"${versionShort}"'/g' "./${versionShort}/Dockerfile"
	sed -i.bak 's!%%MAIN_SHA%%!'"$vgParam1"'!g' "./$versionShort/Dockerfile"  # will be deprecated in the future
	sed -i.bak 's!%%PARAM1%%!'"$vgParam1"'!g' "./$versionShort/Dockerfile"
	sed -i.bak 's!%%ALIAS1%%!'"$vgAlias1"'!g' "./$versionShort/Dockerfile"

	# This .bak thing above and below is a Linux/macOS compatibility fix
	rm "./${versionShort}/Dockerfile.bak"
 
	string="$string --file $versionShort/Dockerfile"

	string="${string} -t ${tagless_image}:${vgVersion}"
	echo $string "string"

	if [[ $versionShort != "$vgVersion" ]]; then
		string="${string}  -t ${tagless_image}:${versionShort}"
	fi

	if [[ -n $vgAlias1 ]]; then
		string="${string}  -t ${tagless_image}:${vgAlias1}"
	fi

	string="$string ."

	echo "$string" >> ./build-images.sh

	# Build a Dockerfile for each variant
	# Currently this only supports shared variants, not local variants
	for variant in "${variants[@]}"; do

		# Check if variant is local, shared, or doesn't exists
		if [[ -f "./variants/${variant}.Dockerfile.template" ]]; then
			variantTemplateFile="./variants/${variant}.Dockerfile.template"
		elif [[ -f "./shared/variants/${variant}.Dockerfile.template" ]]; then
			variantTemplateFile="./shared/variants/${variant}.Dockerfile.template"
		else
			echo "Error: Variant ${variant} doesn't exists. Exiting."
			exit 2
		fi

		# If version/variant directory doesn't exist, create it
		[[ -d "${versionShort}/${variant}" ]] || mkdir "${versionShort}/${variant}"

		sed -e 's!%%PARENT%%!'"$repository"'!g' "${variantTemplateFile}" > "./${versionShort}/${variant}/Dockerfile"
		sed -i.bak 's/%%PARENT_TAG%%/'"${vgVersion}"'/g' "./${versionShort}/${variant}/Dockerfile"

		# This .bak thing above and below is a Linux/macOS compatibility fix
		rm "./${versionShort}/${variant}/Dockerfile.bak"

		string="docker build"
		string="$string --file ${versionShort}/${variant}/Dockerfile"

		string="${string} -t ${tagless_image}:${vgVersion}-${variant}"

		if [[ $versionShort != "$vgVersion" ]]; then
			string="${string}  -t ${tagless_image}:${versionShort}-${variant}"
		fi

		if [[ -n $vgAlias1 ]]; then
			string="${string}  -t ${tagless_image}:${vgAlias1}-${variant}"
		fi

		string="$string ."

		echo "$string" >> ./build-images.sh
	done

	# Build out the ALIASES file. Keeps track of aliases that have been set
	# without losing old versions.
	if [[ -n $vgAlias1 ]]; then
		if [[ -f ALIASES ]]; then
			# Make sure the current alias isn't in the file.
			grep -v "${vgAlias1}" ./ALIASES > ./TEMP && mv ./TEMP ./ALIASES
		fi

		echo "${vgAlias1}=${vgVersion}" >> ALIASES
	fi
done
