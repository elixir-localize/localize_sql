PRIVDIR = ./priv
SRCDIR = c_src

SOURCES = $(SRCDIR)/localize_icu.c
OBJECTS = $(SRCDIR)/localize_icu.o

UNAME_SYS := $(shell uname -s)

# SQLite's load_extension() appends the platform's shared library
# suffix when the given path has none, so the built name has to match
# what SQLite looks for: .dylib on macOS, .so elsewhere.
ifeq ($(UNAME_SYS), Darwin)
  SO_SUFFIX = dylib
  CC ?= cc
  CFLAGS ?= -O3 -Wall -Wextra
  LDFLAGS += -dynamiclib
else
  SO_SUFFIX = so
  CC ?= gcc
  CFLAGS ?= -O3 -Wall -Wextra
  LDFLAGS += -shared
endif

EXTENSION = $(PRIVDIR)/localize_icu.$(SO_SUFFIX)

# The vendored sqlite3ext.h/sqlite3.h are used for declarations only;
# the extension resolves every SQLite call through the api routines
# vtable and never links against libsqlite3.
CFLAGS += -std=c99 -fPIC -I$(SRCDIR)

# ICU detection. On macOS Homebrew's icu4c is keg-only and is now
# installed under a versioned name (icu4c@78), so pkg-config has to be
# pointed at it explicitly. The path is prefixed onto each invocation
# rather than exported because make 3.81 — still the version macOS
# ships — does not reliably pass exported variables into $(shell).
ifeq ($(UNAME_SYS), Darwin)
  HOMEBREW_ICU_PKGCONFIG := $(shell ls -d /opt/homebrew/opt/icu4c*/lib/pkgconfig /usr/local/opt/icu4c*/lib/pkgconfig 2>/dev/null | head -1)
  PKG_CONFIG := PKG_CONFIG_PATH="$(HOMEBREW_ICU_PKGCONFIG):$(PKG_CONFIG_PATH)" pkg-config
else
  PKG_CONFIG := pkg-config
endif

ICU_CFLAGS := $(shell $(PKG_CONFIG) --cflags icu-uc icu-i18n 2>/dev/null)
ICU_LIBS := $(shell $(PKG_CONFIG) --libs icu-uc icu-i18n 2>/dev/null)

ifeq ($(ICU_LIBS),)
  $(error ICU libraries not found. On macOS: brew install icu4c. On Debian/Ubuntu: apt-get install libicu-dev)
endif

all: $(EXTENSION)

clean:
	@rm -f $(EXTENSION) $(OBJECTS)

$(EXTENSION): $(OBJECTS)
	@mkdir -p $(PRIVDIR)
	$(CC) $(OBJECTS) $(LDFLAGS) $(ICU_LIBS) -o $(EXTENSION)

$(SRCDIR)/%.o: $(SRCDIR)/%.c
	$(CC) -c $(CFLAGS) $(ICU_CFLAGS) $< -o $@

.PHONY: all clean
