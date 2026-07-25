#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

static int build_path(char *buffer, size_t size, const char *base, const char *suffix) {
    int written = snprintf(buffer, size, "%s%s", base, suffix);
    return written >= 0 && (size_t)written < size ? 0 : -1;
}

static int env_dimension(const char *name, unsigned short *value) {
    const char *raw = getenv(name);
    char *end = NULL;

    if (raw == NULL || *raw == '\0') {
        return -1;
    }

    errno = 0;
    unsigned long parsed = strtoul(raw, &end, 10);
    if (errno != 0 || *end != '\0' || parsed == 0 || parsed > USHRT_MAX) {
        return -1;
    }

    *value = (unsigned short)parsed;
    return 0;
}

static int terminal_size(unsigned short *rows, unsigned short *columns) {
    struct winsize size = {0};
    char path[64];
    const char *pid = getenv("PID");
    int fd = -1;

    if (env_dimension("ROWS", rows) == 0 && env_dimension("COLS", columns) == 0) {
        return 0;
    }

    if (pid != NULL && strspn(pid, "0123456789") == strlen(pid)) {
        int written = snprintf(path, sizeof(path), "/proc/%s/fd/0", pid);
        if (written > 0 && (size_t)written < sizeof(path)) {
            fd = open(path, O_RDONLY | O_CLOEXEC);
        }
    }
    if (fd < 0) {
        fd = open("/dev/tty", O_RDONLY | O_CLOEXEC);
    }
    if (fd < 0) {
        return -1;
    }

    int result = ioctl(fd, TIOCGWINSZ, &size);
    close(fd);
    if (result < 0 || size.ws_row == 0 || size.ws_col == 0) {
        return -1;
    }

    *rows = size.ws_row;
    *columns = size.ws_col;
    return 0;
}

static char *read_file(const char *path, size_t *length) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        return NULL;
    }

    struct stat info;
    if (fstat(fd, &info) < 0 || info.st_size < 0 || info.st_size > 1024 * 1024) {
        close(fd);
        return NULL;
    }

    size_t size = (size_t)info.st_size;
    char *content = malloc(size + 1);
    if (content == NULL) {
        close(fd);
        return NULL;
    }

    size_t offset = 0;
    while (offset < size) {
        ssize_t count = read(fd, content + offset, size - offset);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            free(content);
            close(fd);
            return NULL;
        }
        offset += (size_t)count;
    }

    close(fd);
    content[size] = '\0';
    *length = size;
    return content;
}

static int write_file(const char *path, const char *content, size_t length) {
    int fd = open(path, O_WRONLY | O_TRUNC | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }

    size_t offset = 0;
    while (offset < length) {
        ssize_t count = write(fd, content + offset, length - offset);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            close(fd);
            return -1;
        }
        offset += (size_t)count;
    }

    return close(fd);
}

static int source_is_newer(const char *source_path, const char *snapshot_path) {
    struct stat source;
    struct stat snapshot;

    if (stat(source_path, &source) < 0 || stat(snapshot_path, &snapshot) < 0) {
        return 1;
    }

    if (source.st_mtim.tv_sec != snapshot.st_mtim.tv_sec) {
        return source.st_mtim.tv_sec > snapshot.st_mtim.tv_sec;
    }
    return source.st_mtim.tv_nsec > snapshot.st_mtim.tv_nsec;
}

static int fallback(const char *config_home, const char *theme_name) {
    char helper[PATH_MAX];
    char theme_path[PATH_MAX];

    if (build_path(helper, sizeof(helper), config_home, "/rmpc/lib/apply_theme") < 0) {
        return 1;
    }

    int written = snprintf(
        theme_path,
        sizeof(theme_path),
        "%s/rmpc/themes/%s.ron",
        config_home,
        theme_name
    );
    if (written < 0 || (size_t)written >= sizeof(theme_path)) {
        return 1;
    }

    if (setenv("RMPC_PREPARE_FORCE", "1", 1) < 0) {
        return 1;
    }
    execl(helper, helper, theme_name, theme_path, (char *)NULL);
    return 1;
}

int main(void) {
    const char *home = getenv("HOME");
    const char *config_home = getenv("XDG_CONFIG_HOME");
    const char *cache_home = getenv("XDG_CACHE_HOME");
    const char *config_override = getenv("RMPC_CONFIG_PATH");
    char default_config_home[PATH_MAX];
    char default_cache_home[PATH_MAX];
    char config_path[PATH_MAX];
    char current_snapshot_path[PATH_MAX];
    char snapshot_path[PATH_MAX];
    char theme_path[PATH_MAX];
    char theme_marker[64];
    const char *theme_names[] = {"pywal16-small", "pywal16", "pywal16-big"};
    unsigned short rows;
    unsigned short columns;
    const char *theme_name;

    if (home == NULL) {
        return 0;
    }
    if (config_home == NULL) {
        if (build_path(default_config_home, sizeof(default_config_home), home, "/.config") < 0) {
            return 0;
        }
        config_home = default_config_home;
    }
    if (cache_home == NULL) {
        if (build_path(default_cache_home, sizeof(default_cache_home), home, "/.cache") < 0) {
            return 0;
        }
        cache_home = default_cache_home;
    }
    if (terminal_size(&rows, &columns) < 0) {
        return 0;
    }

    if (columns < 90 && rows < 30) {
        theme_name = "pywal16-small";
    } else if (columns < 90 || rows < 30) {
        theme_name = "pywal16";
    } else {
        theme_name = "pywal16-big";
    }

    if (config_override != NULL) {
        int written = snprintf(config_path, sizeof(config_path), "%s", config_override);
        if (written < 0 || (size_t)written >= sizeof(config_path)) {
            return 0;
        }
    } else if (build_path(config_path, sizeof(config_path), config_home, "/rmpc/config.ron") < 0) {
        return 0;
    }

    size_t config_length = 0;
    char *config = read_file(config_path, &config_length);
    if (config == NULL) {
        return fallback(config_home, theme_name);
    }

    int marker_length = snprintf(
        theme_marker,
        sizeof(theme_marker),
        "theme: Some(\"%s\")",
        theme_name
    );
    if (marker_length > 0 && (size_t)marker_length < sizeof(theme_marker) &&
        strstr(config, theme_marker) != NULL) {
        free(config);
        return 0;
    }

    const char *current_theme = NULL;
    for (size_t index = 0; index < sizeof(theme_names) / sizeof(theme_names[0]); index++) {
        marker_length = snprintf(
            theme_marker,
            sizeof(theme_marker),
            "theme: Some(\"%s\")",
            theme_names[index]
        );
        if (marker_length > 0 && (size_t)marker_length < sizeof(theme_marker) &&
            strstr(config, theme_marker) != NULL) {
            current_theme = theme_names[index];
            break;
        }
    }
    if (current_theme == NULL) {
        free(config);
        return fallback(config_home, theme_name);
    }

    int written = snprintf(
        current_snapshot_path,
        sizeof(current_snapshot_path),
        "%s/rmpc/configs/%s.ron",
        cache_home,
        current_theme
    );
    if (written < 0 || (size_t)written >= sizeof(current_snapshot_path)) {
        free(config);
        return fallback(config_home, theme_name);
    }

    size_t current_snapshot_length = 0;
    char *current_snapshot = read_file(current_snapshot_path, &current_snapshot_length);
    if (current_snapshot == NULL || current_snapshot_length != config_length ||
        memcmp(current_snapshot, config, config_length) != 0) {
        free(current_snapshot);
        free(config);
        return fallback(config_home, theme_name);
    }
    free(current_snapshot);
    free(config);

    written = snprintf(
        snapshot_path,
        sizeof(snapshot_path),
        "%s/rmpc/configs/%s.ron",
        cache_home,
        theme_name
    );
    if (written < 0 || (size_t)written >= sizeof(snapshot_path)) {
        return fallback(config_home, theme_name);
    }

    written = snprintf(
        theme_path,
        sizeof(theme_path),
        "%s/rmpc/themes/%s.ron",
        config_home,
        theme_name
    );
    if (written < 0 || (size_t)written >= sizeof(theme_path) ||
        source_is_newer(theme_path, snapshot_path)) {
        return fallback(config_home, theme_name);
    }

    size_t snapshot_length = 0;
    char *snapshot = read_file(snapshot_path, &snapshot_length);
    if (snapshot == NULL) {
        return fallback(config_home, theme_name);
    }

    int result = write_file(config_path, snapshot, snapshot_length);
    free(snapshot);
    return result < 0 ? 1 : 0;
}
