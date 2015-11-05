# 
# Copyright (C) 2006,2007 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

# where to build (and put) .ipk packages
OPKG:= \
  IPKG_TMP=$(TMP_DIR)/ipkg \
  IPKG_INSTROOT=$(TARGET_DIR) \
  IPKG_CONF_DIR=$(STAGING_DIR)/etc \
  IPKG_OFFLINE_ROOT=$(TARGET_DIR) \
  $(STAGING_DIR_HOST)/bin/opkg \
	--offline-root $(TARGET_DIR) \
	--force-depends \
	--force-overwrite \
	--force-postinstall \
	--force-maintainer \
	--add-dest root:/ \
	--add-arch all:100 \
	--add-arch $(ARCH_PACKAGES):200

# invoke ipkg-build with some default options
IPKG_BUILD:= \
  ipkg-build -c -o 0 -g 0

IPKG_STATE_DIR:=$(TARGET_DIR)/usr/lib/opkg

define BuildIPKGVariable
ifdef Package/$(1)/$(2)
  $(call shexport,Package/$(1)/$(2))
  $(1)_COMMANDS += var2file "$(call shvar,Package/$(1)/$(2))" $(2);
endif
endef

PARENL :=(
PARENR :=)

dep_split=$(subst :,$(space),$(1))
dep_rem=$(subst !,,$(subst $(strip $(PARENL)),,$(subst $(strip $(PARENR)),,$(word 1,$(call dep_split,$(1))))))
dep_confvar=$(strip $(foreach cond,$(subst ||, ,$(call dep_rem,$(1))),$(CONFIG_$(cond))))
dep_pos=$(if $(call dep_confvar,$(1)),$(call dep_val,$(1)))
dep_neg=$(if $(call dep_confvar,$(1)),,$(call dep_val,$(1)))
dep_if=$(if $(findstring !,$(1)),$(call dep_neg,$(1)),$(call dep_pos,$(1)))
dep_val=$(word 2,$(call dep_split,$(1)))
strip_deps=$(strip $(subst +,,$(filter-out @%,$(1))))
filter_deps=$(foreach dep,$(call strip_deps,$(1)),$(if $(findstring :,$(dep)),$(call dep_if,$(dep)),$(dep)))

ifeq ($(DUMP),)
  define BuildTarget/ipkg
    IPKG_$(1):=$(PACKAGE_DIR)/$(1)_$(VERSION)_$(PKGARCH).ipk
    IDIR_$(1):=$(PKG_BUILD_DIR)/ipkg-$(PKGARCH)/$(1)
    INFO_$(1):=$(IPKG_STATE_DIR)/info/$(1).list
    KEEP_$(1):=$(strip $(call Package/$(1)/conffiles))

    ifeq ($(if $(VARIANT),$(BUILD_VARIANT)),$(VARIANT))
    ifdef Package/$(1)/install
      ifneq ($(CONFIG_PACKAGE_$(1))$(SDK)$(DEVELOPER),)
        compile: $$(IPKG_$(1)) $(STAGING_DIR_ROOT)/stamp/.$(1)_installed

        ifeq ($(CONFIG_PACKAGE_$(1)),y)
          install: $$(INFO_$(1))
        endif
      else
        compile: $(1)-disabled
        $(1)-disabled:
		@echo "WARNING: skipping $(1) -- package not selected"
      endif
    endif
    endif

    IDEPEND_$(1):=$$(call filter_deps,$$(DEPENDS))
  
    $(eval $(call BuildIPKGVariable,$(1),conffiles))
    $(eval $(call BuildIPKGVariable,$(1),preinst))
    $(eval $(call BuildIPKGVariable,$(1),postinst))
    $(eval $(call BuildIPKGVariable,$(1),prerm))
    $(eval $(call BuildIPKGVariable,$(1),postrm))

    $(STAGING_DIR_ROOT)/stamp/.$(1)_installed: $(STAMP_BUILT)
	rm -rf $(STAGING_DIR_ROOT)/tmp-$(1)
	mkdir -p $(STAGING_DIR_ROOT)/stamp $(STAGING_DIR_ROOT)/tmp-$(1)
	$(call Package/$(1)/install,$(STAGING_DIR_ROOT)/tmp-$(1))
	$(call Package/$(1)/install_lib,$(STAGING_DIR_ROOT)/tmp-$(1))
	$(CP) $(STAGING_DIR_ROOT)/tmp-$(1)/. $(STAGING_DIR_ROOT)/
	rm -rf $(STAGING_DIR_ROOT)/tmp-$(1)
	touch $$@

    $$(IPKG_$(1)): $(STAMP_BUILT)
	@rm -f $(PACKAGE_DIR)/$(1)_*
	rm -rf $$(IDIR_$(1))
	mkdir -p $$(IDIR_$(1))/CONTROL
	echo "Package: $(1)" > $$(IDIR_$(1))/CONTROL/control
	echo "Version: $(VERSION)" >> $$(IDIR_$(1))/CONTROL/control
	( \
		DEPENDS='$(EXTRA_DEPENDS)'; \
		for depend in $$(filter-out @%,$$(IDEPEND_$(1))); do \
			DEPENDS=$$$${DEPENDS:+$$$$DEPENDS, }$$$${depend##+}; \
		done; \
		echo "Depends: $$$$DEPENDS"; \
		echo "Provides: $(PROVIDES)"; \
		echo "Source: $(SOURCE)"; \
		echo "Section: $(SECTION)"; \
		echo "Status: unknown $(if $(filter hold,$(PKG_FLAGS)),hold,ok) not-installed"; \
		echo "Essential: $(if $(filter essential,$(PKG_FLAGS)),yes,no)"; \
		echo "Priority: $(PRIORITY)"; \
		echo "Maintainer: $(MAINTAINER)"; \
		echo "Architecture: $(PKGARCH)"; \
		echo "Installed-Size: 0"; \
		echo -n "Description: "; $(SH_FUNC) getvar $(call shvar,Package/$(1)/description) | sed -e 's,^[[:space:]]*, ,g'; \
 	) >> $$(IDIR_$(1))/CONTROL/control
	chmod 644 $$(IDIR_$(1))/CONTROL/control
	$(SH_FUNC) (cd $$(IDIR_$(1))/CONTROL; \
		$($(1)_COMMANDS) \
	)
	$(call Package/$(1)/install,$$(IDIR_$(1)))
	mkdir -p $(PACKAGE_DIR)
	-find $$(IDIR_$(1)) -name 'CVS' -o -name '.svn' -o -name '.#*' | $(XARGS) rm -rf
	$(RSTRIP) $$(IDIR_$(1))

    ifneq ($$(KEEP_$(1)),)
		@( \
			keepfiles=""; \
			for x in $$(KEEP_$(1)); do \
				[ -f "$$(IDIR_$(1))/$$$$x" ] || keepfiles="$$$${keepfiles:+$$$$keepfiles }$$$$x"; \
			done; \
			[ -z "$keepfiles" ] || { \
				mkdir -p $$(IDIR_$(1))/lib/upgrade/keep.d; \
				for x in $$$$keepfiles; do echo $$$$x >> $$(IDIR_$(1))/lib/upgrade/keep.d/$(1); done; \
			}; \
		)
    endif

	$(IPKG_BUILD) $$(IDIR_$(1)) $(PACKAGE_DIR)
	@[ -f $$(IPKG_$(1)) ] || false 

    $$(INFO_$(1)): $$(IPKG_$(1))
	@[ -d $(TARGET_DIR)/tmp ] || mkdir -p $(TARGET_DIR)/tmp
	$(OPKG) install $$(IPKG_$(1))
	$(if $(filter-out essential,$(PKG_FLAGS)),for flag in $(filter-out essential,$(PKG_FLAGS)); do $(OPKG) flag $$$$flag $(1); done)

    $(1)-clean:
	rm -f $(PACKAGE_DIR)/$(1)_*

    clean: $(1)-clean

  endef
endif
