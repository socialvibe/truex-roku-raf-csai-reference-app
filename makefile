# Copyright (c) 2019 true[X], Inc. All rights reserved.

APPNAME = truex-roku-raf-csai-reference-app
IMPORTS =
ROKU_TEST_ID = 1
ROKU_TEST_WAIT_DURATION = 5

# BRANCH_NAME is set by Jenkins. When on a release branch, the following will evaluate to `rc`, while on a develop branch, it will be left alone (`develop`).
RC_DEVELOP = $(shell echo $$BRANCH_NAME | sed "s/release.*/rc/")

ZIP_EXCLUDE = -x *.sh -x makefile -x dist\* -x *app.mk* -x *README* -x *rokuTarget* -x *.svn* -x *.git* -x *.DS_Store* -x out\* -x packages\* -x design\* -x node_modules/**\* -x node_modules -x .buildpath* -x .project* -x renderer\* -x backup\* -x *.code-workspace

APPSROOT = .
include $(APPSROOT)/app.mk

ARTIFACTDIR := $(DISTREL)/$(APPNAME)

update_truex_lib_uri:
	sed -i '' 's/ComponentLibrary id=\"TruexAdRendererLib\" uri=\".*\"/ComponentLibrary id=\"TruexAdRendererLib\" uri=\"http:\/\/ctv.truex.com\/roku\/v${MAJOR}_${MINOR}\/${RC_DEVELOP}\/${LIBNAME}-v${MAJOR}.${MINOR}.${BUILD_NUM}-${BUILD_HASH}.pkg\"/' ./components/MainScene.xml ;\

# deploy `TruexRokuReferenceApp` side-load capable zip file to s3
# append the major, minor then rc or develop components to the upload path.
# Note: the MAJOR, MINOR, BUILD_NUM, BUILD_HASH env variables are set upstream by the Jenkins system (TAR's Jenkinsfile)
deploy: update_truex_lib_uri $(APPNAME)
	S3_BUCKET=$$(grep s3_bucket ~/Library/Truex/Roku/target | sed 's/s3_bucket=//') ;\
	echo $$S3_BUCKET ;\
	echo $$MAJOR ;\
	echo $$MINOR ;\
	echo $$BUILD_NUM ;\
	echo $$BUILD_HASH ;\
	aws s3 cp dist/apps/${APPNAME}.zip s3://$$S3_BUCKET/roku/v${MAJOR}_${MINOR}/${RC_DEVELOP}/${APPNAME}-${RC_DEVELOP}-v${MAJOR}.${MINOR}.${BUILD_NUM}-${BUILD_HASH}.zip --acl public-read ;\

.PHONY: github-artifact
github-artifact: manifest
	@$(ECHO) "  >> creating destination directory $(ARTIFACTDIR)"
	@rm -rf $(ARTIFACTDIR); \
	mkdir -p $(ARTIFACTDIR); \

	@$(ECHO) "  >> setting directory permissions for $(ARTIFACTDIR)"
	@if [ ! -w $(ARTIFACTDIR) ]; then \
		chmod 755 $(ARTIFACTDIR); \
	fi

	@$(ECHO) "  >> copying app sources to $(ARTIFACTDIR)"
	@cp -R $(SOURCEDIR)/components $(ARTIFACTDIR)/; \
	cp -R $(SOURCEDIR)/source $(ARTIFACTDIR)/; \
	cp -R $(SOURCEDIR)/images $(ARTIFACTDIR)/; \
	cp -R $(SOURCEDIR)/fonts $(ARTIFACTDIR)/; \
	cp -R $(SOURCEDIR)/res $(ARTIFACTDIR)/; \
	cp $(SOURCEDIR)/manifest $(ARTIFACTDIR)/

	@$(ECHO) "$(COLOR_DONE)**** packaging '$(APPNAME)' complete ****$(COLOR_OFF)"
