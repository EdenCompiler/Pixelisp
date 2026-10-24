/* Native adapters for Pixelisp. No callbacks enter the Lisp runtime. */
#define _GNU_SOURCE
#include <SDL.h>
#include <SDL_mixer.h>
#include <linux/videodev2.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <time.h>
#include <limits.h>

static __thread char px_error[512];

const char *px_native_error(void) { return px_error; }

static void set_error(const char *message) {
    snprintf(px_error, sizeof px_error, "%s", message);
}

static int fail(const char *operation) {
    snprintf(px_error, sizeof px_error, "%s: %s", operation, strerror(errno));
    return -1;
}

/* Resolve libv4l2 lazily so systems without camera support can still load the
   rest of Pixelisp. All symbols must be present before capture is advertised. */
static void *v4l_library;
static pthread_mutex_t v4l_lock = PTHREAD_MUTEX_INITIALIZER;
static int (*vopen)(const char *, int, ...);
static int (*vclose)(int);
static int (*vioctl)(int, unsigned long, ...);
static void *(*vmmap)(void *, size_t, int, int, int, int64_t);
static int (*vmunmap)(void *, size_t);

int px_camera_available(void) {
    pthread_mutex_lock(&v4l_lock);
    if (!v4l_library) {
        v4l_library = dlopen("libv4l2.so.0", RTLD_NOW | RTLD_LOCAL);
        if (v4l_library) {
            *(void **)(&vopen) = dlsym(v4l_library, "v4l2_open");
            *(void **)(&vclose) = dlsym(v4l_library, "v4l2_close");
            *(void **)(&vioctl) = dlsym(v4l_library, "v4l2_ioctl");
            *(void **)(&vmmap) = dlsym(v4l_library, "v4l2_mmap");
            *(void **)(&vmunmap) = dlsym(v4l_library, "v4l2_munmap");
        }
    }
    const int available = v4l_library && vopen && vclose && vioctl && vmmap && vmunmap;
    if (!available) set_error("libv4l2.so.0 is unavailable or incomplete");
    pthread_mutex_unlock(&v4l_lock);
    return available;
}

static int xioctl(int fd, unsigned long request, void *argument) {
    int result;
    do {
        result = vioctl(fd, request, argument);
    } while (result < 0 && errno == EINTR);
    return result;
}

int px_camera_probe(const char *path) {
    if (!px_camera_available()) return 0;

    const int fd = vopen(path, O_RDWR | O_NONBLOCK);
    if (fd < 0) return 0;

    struct v4l2_capability capabilities;
    memset(&capabilities, 0, sizeof capabilities);
    const int result = xioctl(fd, VIDIOC_QUERYCAP, &capabilities);
    vclose(fd);

    const unsigned int flags = (capabilities.capabilities & V4L2_CAP_DEVICE_CAPS)
        ? capabilities.device_caps : capabilities.capabilities;
    return result == 0 && (flags & V4L2_CAP_VIDEO_CAPTURE) &&
        (flags & V4L2_CAP_STREAMING);
}

struct px_buffer {
    void *data;
    size_t length;
};

struct px_camera {
    int fd;
    unsigned int width;
    unsigned int height;
    size_t pitch;
    unsigned int buffer_count;
    struct px_buffer *buffers;
    int streaming;
};

static void unmap_camera_buffers(struct px_camera *camera) {
    if (!camera->buffers) return;
    for (unsigned int index = 0; index < camera->buffer_count; index++) {
        if (camera->buffers[index].data && camera->buffers[index].data != MAP_FAILED)
            vmunmap(camera->buffers[index].data, camera->buffers[index].length);
    }
    free(camera->buffers);
    camera->buffers = NULL;
    camera->buffer_count = 0;
}

void px_camera_close(struct px_camera *camera) {
    if (!camera) return;

    if (camera->streaming) {
        enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        xioctl(camera->fd, VIDIOC_STREAMOFF, &type);
        camera->streaming = 0;
    }
    unmap_camera_buffers(camera);
    if (camera->fd >= 0) vclose(camera->fd);
    free(camera);
}

static int allocate_camera_buffers(struct px_camera *camera) {
    struct v4l2_requestbuffers request;
    memset(&request, 0, sizeof request);
    request.count = 4;
    request.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    request.memory = V4L2_MEMORY_MMAP;
    if (xioctl(camera->fd, VIDIOC_REQBUFS, &request) < 0)
        return fail("allocate camera buffers");
    if (!request.count) {
        set_error("camera supplied no streaming buffers");
        return -1;
    }

    camera->buffers = calloc(request.count, sizeof *camera->buffers);
    if (!camera->buffers) return fail("allocate camera mapping table");
    camera->buffer_count = request.count;

    for (unsigned int index = 0; index < camera->buffer_count; index++) {
        struct v4l2_buffer buffer;
        memset(&buffer, 0, sizeof buffer);
        buffer.type = request.type;
        buffer.memory = request.memory;
        buffer.index = index;
        if (xioctl(camera->fd, VIDIOC_QUERYBUF, &buffer) < 0)
            return fail("query camera buffer");

        camera->buffers[index].length = buffer.length;
        camera->buffers[index].data = vmmap(NULL, buffer.length,
                                            PROT_READ | PROT_WRITE, MAP_SHARED,
                                            camera->fd, buffer.m.offset);
        if (camera->buffers[index].data == MAP_FAILED)
            return fail("map camera buffer");
        if (xioctl(camera->fd, VIDIOC_QBUF, &buffer) < 0)
            return fail("queue camera buffer");
    }
    return 0;
}

struct px_camera *px_camera_open(const char *path, int requested_width,
                                 int requested_height) {
    if (!px_camera_available()) return NULL;
    if (requested_width <= 0 || requested_height <= 0) {
        set_error("camera dimensions must be positive");
        return NULL;
    }

    struct px_camera *camera = calloc(1, sizeof *camera);
    if (!camera) {
        fail("allocate camera");
        return NULL;
    }
    camera->fd = -1;
    camera->fd = vopen(path, O_RDWR | O_NONBLOCK);
    if (camera->fd < 0) {
        fail("open camera");
        free(camera);
        return NULL;
    }

    struct v4l2_format format;
    memset(&format, 0, sizeof format);
    format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    format.fmt.pix.width = (unsigned int)requested_width;
    format.fmt.pix.height = (unsigned int)requested_height;
    format.fmt.pix.pixelformat = V4L2_PIX_FMT_RGB24;
    format.fmt.pix.field = V4L2_FIELD_ANY;
    if (xioctl(camera->fd, VIDIOC_S_FMT, &format) < 0) {
        fail("negotiate RGB24");
        goto error;
    }
    if (format.fmt.pix.pixelformat != V4L2_PIX_FMT_RGB24) {
        set_error("camera cannot provide RGB24 through libv4l2");
        goto error;
    }
    camera->width = format.fmt.pix.width;
    camera->height = format.fmt.pix.height;
    size_t minimum_pitch;
    size_t image_bytes;
    if (!camera->width || !camera->height ||
        __builtin_mul_overflow((size_t)camera->width, (size_t)3, &minimum_pitch) ||
        __builtin_mul_overflow(minimum_pitch, (size_t)camera->height, &image_bytes)) {
        set_error("camera negotiated invalid or oversized dimensions");
        goto error;
    }

    (void)image_bytes;
    camera->pitch = format.fmt.pix.bytesperline;
    if (camera->pitch < minimum_pitch) camera->pitch = minimum_pitch;
    if (camera->pitch > SIZE_MAX / camera->height) {
        set_error("camera negotiated an oversized row stride");
        goto error;
    }

    if (allocate_camera_buffers(camera) < 0) goto error;
    enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (xioctl(camera->fd, VIDIOC_STREAMON, &type) < 0) {
        fail("start camera stream");
        goto error;
    }
    camera->streaming = 1;
    return camera;

error:
    px_camera_close(camera);
    return NULL;
}

int px_camera_width(struct px_camera *camera) { return (int)camera->width; }
int px_camera_height(struct px_camera *camera) { return (int)camera->height; }

/* Retry interrupted polls against a monotonic deadline so EINTR cannot turn a
   caller's finite frame timeout into an unbounded wait. */
static int poll_camera(struct px_camera *camera, int timeout_ms) {
    struct timespec deadline;
    if (timeout_ms >= 0) {
        clock_gettime(CLOCK_MONOTONIC, &deadline);
        deadline.tv_sec += timeout_ms / 1000;
        deadline.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
        if (deadline.tv_nsec >= 1000000000L) {
            deadline.tv_sec++;
            deadline.tv_nsec -= 1000000000L;
        }
    }

    struct pollfd descriptor = { .fd = camera->fd, .events = POLLIN, .revents = 0 };
    int wait_ms = timeout_ms;
    int result;
    do {
        result = poll(&descriptor, 1, wait_ms);
        if (result < 0 && errno == EINTR && timeout_ms >= 0) {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            const int64_t remaining_ns =
                (int64_t)(deadline.tv_sec - now.tv_sec) * 1000000000LL +
                (deadline.tv_nsec - now.tv_nsec);
            if (remaining_ns <= 0) return 0;
            const int64_t remaining_ms = (remaining_ns + 999999LL) / 1000000LL;
            wait_ms = remaining_ms > INT_MAX ? INT_MAX : (int)remaining_ms;
        }
    } while (result < 0 && errno == EINTR);

    if (result < 0) return fail("poll camera");
    if (result > 0 && (descriptor.revents & (POLLERR | POLLHUP | POLLNVAL))) {
        set_error("camera disconnected or reported an I/O error");
        return -1;
    }
    return result > 0 && (descriptor.revents & POLLIN) ? 1 : 0;
}

int px_camera_ready(struct px_camera *camera, int timeout_ms) {
    return poll_camera(camera, timeout_ms);
}

int px_camera_frame(struct px_camera *camera, unsigned char *output,
                    size_t capacity, int timeout_ms) {
    const size_t row_bytes = (size_t)camera->width * 3;
    const size_t output_bytes = row_bytes * camera->height;
    if (capacity < output_bytes) {
        set_error("camera output buffer is too small");
        return -1;
    }

    const int ready = poll_camera(camera, timeout_ms);
    if (ready <= 0) return ready;

    struct v4l2_buffer buffer;
    memset(&buffer, 0, sizeof buffer);
    buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buffer.memory = V4L2_MEMORY_MMAP;
    if (xioctl(camera->fd, VIDIOC_DQBUF, &buffer) < 0) {
        if (errno == EAGAIN) return 0;
        return fail("dequeue camera frame");
    }

    int valid = buffer.index < camera->buffer_count;
    if (valid) {
        const struct px_buffer *mapped = &camera->buffers[buffer.index];
        const size_t required_bytes = camera->pitch * (camera->height - 1) + row_bytes;
        valid = buffer.bytesused >= required_bytes &&
            buffer.bytesused <= mapped->length && required_bytes <= mapped->length;
        if (valid) {
            const unsigned char *pixels = mapped->data;
            for (unsigned int y = 0; y < camera->height; y++) {
                memcpy(output + (size_t)y * row_bytes,
                       pixels + (size_t)y * camera->pitch, row_bytes);
            }
        }
    }

    const int requeue_result = xioctl(camera->fd, VIDIOC_QBUF, &buffer);
    if (requeue_result < 0) return fail("requeue camera frame");
    if (!valid) {
        set_error("camera returned a truncated or oversized frame");
        return -1;
    }
    return 1;
}

static unsigned int control_id(int control) {
    switch (control) {
    case 0: return V4L2_CID_BRIGHTNESS;
    case 1: return V4L2_CID_HFLIP;
    case 2: return V4L2_CID_VFLIP;
    case 3: return V4L2_CID_CONTRAST;
    case 4: return V4L2_CID_SATURATION;
    case 5: return V4L2_CID_HUE;
    case 6: return V4L2_CID_GAIN;
    default: return (unsigned int)control;
    }
}

int px_camera_control_info(struct px_camera *camera, int control,
                           int *minimum, int *maximum, int *step, int *default_value) {
    struct v4l2_queryctrl query;
    memset(&query, 0, sizeof query);
    query.id = control_id(control);
    if (xioctl(camera->fd, VIDIOC_QUERYCTRL, &query) < 0 ||
        (query.flags & V4L2_CTRL_FLAG_DISABLED)) return 0;
    *minimum = query.minimum;
    *maximum = query.maximum;
    *step = query.step;
    *default_value = query.default_value;
    return 1;
}

int px_camera_get_control(struct px_camera *camera, int control, int *value) {
    struct v4l2_control setting = { .id = control_id(control), .value = 0 };
    if (xioctl(camera->fd, VIDIOC_G_CTRL, &setting) < 0)
        return fail("get camera control");
    *value = setting.value;
    return 0;
}

int px_camera_set_control(struct px_camera *camera, int control, int value) {
    struct v4l2_control setting = { .id = control_id(control), .value = value };
    if (xioctl(camera->fd, VIDIOC_S_CTRL, &setting) < 0)
        return fail("set camera control");
    return 0;
}

/* Bounded postmix capture. The callback copies bytes under a native mutex and
   never calls Lisp, allocates memory, or waits for Lisp to consume the ring. */
static pthread_mutex_t capture_mutex = PTHREAD_MUTEX_INITIALIZER;
static unsigned char *capture_data;
static size_t capture_capacity;
static size_t capture_start;
static size_t capture_length;

static void capture_callback(void *unused, Uint8 *stream, int length) {
    (void)unused;
    if (length <= 0) return;

    pthread_mutex_lock(&capture_mutex);
    if (capture_data) {
        size_t copy_length = (size_t)length;
        if (copy_length > capture_capacity) {
            stream += copy_length - capture_capacity;
            copy_length = capture_capacity;
        }

        const size_t overflow = capture_length + copy_length > capture_capacity
            ? capture_length + copy_length - capture_capacity : 0;
        capture_start = (capture_start + overflow) % capture_capacity;
        capture_length -= overflow;

        const size_t write_at = (capture_start + capture_length) % capture_capacity;
        const size_t first_length = copy_length < capture_capacity - write_at
            ? copy_length : capture_capacity - write_at;
        memcpy(capture_data + write_at, stream, first_length);
        memcpy(capture_data, stream + first_length, copy_length - first_length);
        capture_length += copy_length;
    }
    pthread_mutex_unlock(&capture_mutex);
}

void px_postmix_stop(void) {
    /* SDL_mixer disables the callback before the ring memory is released. */
    Mix_SetPostMix(NULL, NULL);
    pthread_mutex_lock(&capture_mutex);
    free(capture_data);
    capture_data = NULL;
    capture_capacity = 0;
    capture_start = 0;
    capture_length = 0;
    pthread_mutex_unlock(&capture_mutex);
}

int px_postmix_start(size_t capacity) {
    int frequency;
    int channels;
    Uint16 format;
    if (!Mix_QuerySpec(&frequency, &format, &channels)) {
        set_error("mixer must be initialized before postmix capture");
        return -1;
    }
    (void)frequency;
    (void)format;
    (void)channels;

    if (capacity < 4096) capacity = 4096;
    px_postmix_stop();

    unsigned char *buffer = malloc(capacity);
    if (!buffer) return fail("allocate postmix buffer");
    pthread_mutex_lock(&capture_mutex);
    capture_data = buffer;
    capture_capacity = capacity;
    pthread_mutex_unlock(&capture_mutex);
    Mix_SetPostMix(capture_callback, NULL);
    return 0;
}

size_t px_postmix_read(unsigned char *output, size_t capacity) {
    pthread_mutex_lock(&capture_mutex);
    const size_t count = capture_length < capacity ? capture_length : capacity;
    if (count) {
        const size_t first_length = count < capture_capacity - capture_start
            ? count : capture_capacity - capture_start;
        memcpy(output, capture_data + capture_start, first_length);
        memcpy(output + first_length, capture_data, count - first_length);
        capture_start = (capture_start + count) % capture_capacity;
        capture_length -= count;
    }
    pthread_mutex_unlock(&capture_mutex);
    return count;
}
