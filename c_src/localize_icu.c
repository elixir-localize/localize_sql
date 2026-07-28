/*
** localize_icu — ICU collation and case mapping for SQLite.
**
** A SQLite loadable extension that gives SQLite the same ICU collations
** PostgreSQL's initdb imports into pg_catalog, under the same names, so
** that a query written against one database sorts identically on the
** other.
**
** Collations are registered lazily. The extension installs a
** sqlite3_collation_needed() handler, so the first statement to mention
** a collation SQLite does not know causes that collation to be built:
**
**     SELECT word FROM words ORDER BY word COLLATE "de-x-icu";
**     SELECT word FROM words ORDER BY word COLLATE "de-u-co-phonebk-x-icu";
**
** The name is a BCP 47 language tag with PostgreSQL's "-x-icu" suffix
** stripped, converted to an ICU locale by uloc_forLanguageTag() and
** opened with ucol_open() — the same pair of calls PostgreSQL uses in
** pg_locale.c, which is what makes the orderings agree. Every tag ICU
** understands works, including the -u- tailorings (-u-co-phonebk,
** -u-ks-level1, -u-kn-true) that PostgreSQL requires a CREATE COLLATION
** for. SQLite needs no DDL: a collation here is a per-connection
** runtime registration, not a schema object.
**
** The extension also registers two-argument upper(X,L), lower(X,L) and
** title(X,L). SQLite's COLLATE affects comparison only, never case
** mapping, and SQLite has no initcap, so locale-correct case conversion
** has to come from ICU directly. Only the two-argument forms are
** registered; SQLite dispatches on arity, so the one-argument builtins
** are left alone.
**
** Build: see c_src/Makefile. This file links against ICU but never
** against SQLite — every SQLite call goes through the sqlite3_api
** routines vtable supplied to the entry point.
*/

#include "sqlite3ext.h"
SQLITE_EXTENSION_INIT1

#include <string.h>

#include <unicode/ucasemap.h>
#include <unicode/ucol.h>
#include <unicode/uloc.h>
#include <unicode/utypes.h>

/*
** PostgreSQL names each ICU collation after its BCP 47 locale
** identifier with this suffix appended: "de-x-icu", "und-x-icu".
** Accepted on input and stripped before the tag reaches ICU, so both
** "de-x-icu" and a bare "de" resolve to the same collator.
*/
#define LOCALIZE_ICU_SUFFIX "-x-icu"
#define LOCALIZE_ICU_SUFFIX_LEN 6

/* Longest accepted collation name. A tag carrying every collation
** relevant -u- keyword is well under this. */
#define LOCALIZE_ICU_MAX_NAME 256

#define LOCALIZE_ICU_LOWER 0
#define LOCALIZE_ICU_UPPER 1
#define LOCALIZE_ICU_TITLE 2

/*
** Per-connection state for one of the case mapping functions.
**
** The UCaseMap is cached across calls because ucasemap_open() builds a
** break iterator for title casing, which is far more expensive than the
** mapping itself. A query almost always passes the same locale to every
** row, so a single entry keyed on the last locale used hits nearly
** always. The cache needs no locking: functions are registered per
** connection and a pooled connection is used by one process at a time.
*/
typedef struct LocalizeIcuCase {
  int which;
  UCaseMap *case_map;
  char locale[ULOC_FULLNAME_CAPACITY];
} LocalizeIcuCase;

/*
** Convert a collation name or language tag to an ICU locale identifier.
** Returns non-zero on success.
**
** An unknown but well formed tag is not an error here: ICU resolves it
** by falling back toward the root locale, which is both its documented
** behaviour and what PostgreSQL does for a collation created at the
** default icu_validation_level. A malformed tag leaves the collation
** unregistered, so SQLite reports its own "no such collation sequence"
** error.
**
** Detecting malformed tags takes more than checking the status.
** uloc_forLanguageTag() parses as much as it can and stops at the first
** ill formed subtag without reporting failure, so "not a tag!!" would
** otherwise be accepted as language "not" and silently resolve to the
** root collator. Requiring it to consume the whole tag is the same
** check PostgreSQL applies in icu_language_tag().
*/
static int localize_icu_locale(const char *name, char *locale, int32_t locale_size) {
  char tag[LOCALIZE_ICU_MAX_NAME];
  size_t name_len;
  int32_t parsed_len = 0;
  UErrorCode status = U_ZERO_ERROR;

  if (name == NULL) {
    return 0;
  }

  name_len = strlen(name);
  if (name_len >= sizeof(tag)) {
    return 0;
  }

  /* SQLite compares collation names case insensitively, so the suffix
  ** is matched the same way. */
  if (name_len > (size_t)LOCALIZE_ICU_SUFFIX_LEN &&
      sqlite3_strnicmp(name + name_len - LOCALIZE_ICU_SUFFIX_LEN, LOCALIZE_ICU_SUFFIX,
                       LOCALIZE_ICU_SUFFIX_LEN) == 0) {
    name_len -= (size_t)LOCALIZE_ICU_SUFFIX_LEN;
  }

  if (name_len == 0) {
    return 0;
  }

  memcpy(tag, name, name_len);
  tag[name_len] = '\0';

  uloc_forLanguageTag(tag, locale, locale_size, &parsed_len, &status);
  if (U_FAILURE(status) || (size_t)parsed_len != name_len) {
    return 0;
  }

  return 1;
}

/*
** Compare two UTF-8 strings with an ICU collator.
**
** ucol_strcollUTF8() collates UTF-8 directly, avoiding the UTF-16
** conversion of every string on every comparison that ucol_strcoll()
** would impose on what is the hottest path in a sort.
*/
static int localize_icu_compare(void *collator, int left_size, const void *left, int right_size,
                                const void *right) {
  UErrorCode status = U_ZERO_ERROR;
  UCollationResult result;

  result = ucol_strcollUTF8((UCollator *)collator, (const char *)left, left_size,
                            (const char *)right, right_size, &status);

  if (U_FAILURE(status)) {
    /* Fall back to a byte comparison. A sort that cannot collate should
    ** still terminate with a consistent ordering rather than produce a
    ** comparator that violates transitivity. */
    int shared = left_size < right_size ? left_size : right_size;
    int order = shared > 0 ? memcmp(left, right, (size_t)shared) : 0;

    if (order != 0) {
      return order < 0 ? -1 : 1;
    }

    if (left_size == right_size) {
      return 0;
    }

    return left_size < right_size ? -1 : 1;
  }

  return (int)result;
}

static void localize_icu_close_collator(void *collator) {
  ucol_close((UCollator *)collator);
}

/*
** Build and register the collation SQLite just asked for. Invoked by
** SQLite when a statement names a collation the connection does not
** have.
*/
static void localize_icu_collation_needed(void *unused, sqlite3 *db, int text_rep,
                                          const char *name) {
  char locale[ULOC_FULLNAME_CAPACITY];
  UErrorCode status = U_ZERO_ERROR;
  UCollator *collator;

  (void)unused;
  (void)text_rep;

  if (!localize_icu_locale(name, locale, (int32_t)sizeof(locale))) {
    return;
  }

  collator = ucol_open(locale, &status);
  if (U_FAILURE(status) || collator == NULL) {
    if (collator != NULL) {
      ucol_close(collator);
    }
    return;
  }

  /* Registered for UTF-8 whatever encoding SQLite asked for; SQLite
  ** converts as needed. */
  if (sqlite3_create_collation_v2(db, name, SQLITE_UTF8, collator, localize_icu_compare,
                                  localize_icu_close_collator) != SQLITE_OK) {
    /* The destructor is not run when registration fails. */
    ucol_close(collator);
  }
}

/*
** Return the cached UCaseMap for `locale`, opening a new one if the
** locale differs from the cached entry. Returns NULL on failure.
*/
static UCaseMap *localize_icu_case_map(LocalizeIcuCase *state, const char *locale) {
  UErrorCode status = U_ZERO_ERROR;
  UCaseMap *case_map;

  if (state->case_map != NULL && strcmp(state->locale, locale) == 0) {
    return state->case_map;
  }

  case_map = ucasemap_open(locale, 0, &status);
  if (U_FAILURE(status) || case_map == NULL) {
    if (case_map != NULL) {
      ucasemap_close(case_map);
    }
    return NULL;
  }

  if (state->case_map != NULL) {
    ucasemap_close(state->case_map);
  }

  sqlite3_snprintf((int)sizeof(state->locale), state->locale, "%s", locale);
  state->case_map = case_map;

  return case_map;
}

static int32_t localize_icu_map_case(int which, UCaseMap *case_map, char *dest, int32_t dest_size,
                                     const char *source, int32_t source_size, UErrorCode *status) {
  switch (which) {
    case LOCALIZE_ICU_UPPER:
      return ucasemap_utf8ToUpper(case_map, dest, dest_size, source, source_size, status);

    case LOCALIZE_ICU_TITLE:
      return ucasemap_utf8ToTitle(case_map, dest, dest_size, source, source_size, status);

    default:
      return ucasemap_utf8ToLower(case_map, dest, dest_size, source, source_size, status);
  }
}

/*
** upper(X, locale), lower(X, locale) and title(X, locale).
**
** `locale` accepts a bare language tag ("tr") or a collation name
** ("tr-x-icu"), so the same resolved name can be passed to COLLATE and
** to these functions.
*/
static void localize_icu_case_function(sqlite3_context *context, int argc, sqlite3_value **argv) {
  LocalizeIcuCase *state = (LocalizeIcuCase *)sqlite3_user_data(context);
  char locale[ULOC_FULLNAME_CAPACITY];
  UErrorCode status = U_ZERO_ERROR;
  UCaseMap *case_map;
  const char *source;
  int32_t source_size;
  int32_t dest_size;
  int32_t written;
  char *dest;

  (void)argc;

  /* A NULL input yields NULL, as SQLite's own upper()/lower() do. */
  if (sqlite3_value_type(argv[0]) == SQLITE_NULL) {
    return;
  }

  if (sqlite3_value_type(argv[1]) == SQLITE_NULL) {
    /* The root locale: ICU's language neutral case mapping. */
    locale[0] = '\0';
  } else if (!localize_icu_locale((const char *)sqlite3_value_text(argv[1]), locale,
                                  (int32_t)sizeof(locale))) {
    sqlite3_result_error(context, "localize_icu: unrecognized locale", -1);
    return;
  }

  source = (const char *)sqlite3_value_text(argv[0]);
  source_size = sqlite3_value_bytes(argv[0]);
  if (source == NULL) {
    return;
  }

  case_map = localize_icu_case_map(state, locale);
  if (case_map == NULL) {
    sqlite3_result_error(context, "localize_icu: could not open ICU case map", -1);
    return;
  }

  /* Case mapping can lengthen a string (ß uppercases to SS), so start
  ** with headroom and grow once if ICU reports it was not enough.
  ** SQLITE_MAX_LENGTH keeps source_size well inside int32 range. */
  dest_size = source_size + 32;
  dest = (char *)sqlite3_malloc(dest_size);
  if (dest == NULL) {
    sqlite3_result_error_nomem(context);
    return;
  }

  written = localize_icu_map_case(state->which, case_map, dest, dest_size, source, source_size,
                                  &status);

  if (status == U_BUFFER_OVERFLOW_ERROR) {
    char *grown = (char *)sqlite3_realloc(dest, written + 1);

    if (grown == NULL) {
      sqlite3_free(dest);
      sqlite3_result_error_nomem(context);
      return;
    }

    dest = grown;
    dest_size = written + 1;
    status = U_ZERO_ERROR;
    written = localize_icu_map_case(state->which, case_map, dest, dest_size, source, source_size,
                                    &status);
  }

  if (U_FAILURE(status)) {
    sqlite3_free(dest);
    sqlite3_result_error(context, "localize_icu: case mapping failed", -1);
    return;
  }

  sqlite3_result_text(context, dest, written, sqlite3_free);
}

static void localize_icu_destroy_case(void *state) {
  LocalizeIcuCase *case_state = (LocalizeIcuCase *)state;

  if (case_state->case_map != NULL) {
    ucasemap_close(case_state->case_map);
  }

  sqlite3_free(case_state);
}

static int localize_icu_register_case(sqlite3 *db, const char *name, int which) {
  LocalizeIcuCase *state = (LocalizeIcuCase *)sqlite3_malloc((int)sizeof(LocalizeIcuCase));

  if (state == NULL) {
    return SQLITE_NOMEM;
  }

  memset(state, 0, sizeof(*state));
  state->which = which;

  /* sqlite3_create_function_v2 runs the destructor even when
  ** registration fails, so `state` is never leaked here. */
  return sqlite3_create_function_v2(db, name, 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC | SQLITE_INNOCUOUS,
                                    state, localize_icu_case_function, NULL, NULL,
                                    localize_icu_destroy_case);
}

#ifdef _WIN32
__declspec(dllexport)
#endif
    /*
    ** Entry point. SQLite derives this symbol from the file name, so the
    ** built library must stay named localize_icu.{so,dylib} for
    ** load_extension() to find it without an explicit entry point
    ** argument — which is how exqlite's :load_extensions calls it.
    */
    int
    sqlite3_localizeicu_init(sqlite3 *db, char **error_message,
                             const sqlite3_api_routines *api_routines) {
  int result;

  SQLITE_EXTENSION_INIT2(api_routines);
  (void)error_message;

  result = sqlite3_collation_needed(db, NULL, localize_icu_collation_needed);
  if (result != SQLITE_OK) {
    return result;
  }

  result = localize_icu_register_case(db, "lower", LOCALIZE_ICU_LOWER);
  if (result != SQLITE_OK) {
    return result;
  }

  result = localize_icu_register_case(db, "upper", LOCALIZE_ICU_UPPER);
  if (result != SQLITE_OK) {
    return result;
  }

  result = localize_icu_register_case(db, "title", LOCALIZE_ICU_TITLE);
  if (result != SQLITE_OK) {
    return result;
  }

  /* Keep the library resident: a connection pool loads it once per
  ** connection, and the collators registered above hold function
  ** pointers into it. */
  return SQLITE_OK_LOAD_PERMANENTLY;
}
