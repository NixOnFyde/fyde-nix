#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <unistd.h>

static void fatal_error(const char *context_message) {
  perror(context_message);
  exit(1);
}

int main(void) {
  if (access("/dev/uinput", W_OK) != 0) {
    system("modprobe uinput 2>/dev/null");
  }

  int uinput_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
  if (uinput_fd < 0) {
    fatal_error("open /dev/uinput");
  }

  if (ioctl(uinput_fd, UI_SET_EVBIT, EV_KEY) < 0) {
    fatal_error("UI_SET_EVBIT EV_KEY");
  }
  if (ioctl(uinput_fd, UI_SET_KEYBIT, KEY_UNKNOWN) < 0) {
    fatal_error("UI_SET_KEYBIT KEY_UNKNOWN");
  }

  struct uinput_setup device_setup = {
      .name = "fydetab-wake-activity",
      .id =
          {
              .bustype = BUS_VIRTUAL,
              .vendor = 0x0001,
              .product = 0x0001,
              .version = 1,
          },
  };

  if (ioctl(uinput_fd, UI_DEV_SETUP, &device_setup) < 0) {
    fatal_error("UI_DEV_SETUP");
  }
  if (ioctl(uinput_fd, UI_DEV_CREATE) < 0) {
    fatal_error("UI_DEV_CREATE");
  }

  // Allow input subsystem time to register the virtual device
  usleep(500 * 1000);

  struct input_event input_event_buffer;
  memset(&input_event_buffer, 0, sizeof(input_event_buffer));

  // Send key down event
  gettimeofday(&input_event_buffer.time, NULL);
  input_event_buffer.type = EV_KEY;
  input_event_buffer.code = KEY_UNKNOWN;
  input_event_buffer.value = 1;
  if (write(uinput_fd, &input_event_buffer, sizeof(input_event_buffer)) < 0) {
    fatal_error("write key down");
  }

  input_event_buffer.type = EV_SYN;
  input_event_buffer.code = SYN_REPORT;
  input_event_buffer.value = 0;
  if (write(uinput_fd, &input_event_buffer, sizeof(input_event_buffer)) < 0) {
    fatal_error("write syn");
  }

  // Send key up event
  gettimeofday(&input_event_buffer.time, NULL);
  input_event_buffer.type = EV_KEY;
  input_event_buffer.code = KEY_UNKNOWN;
  input_event_buffer.value = 0;
  if (write(uinput_fd, &input_event_buffer, sizeof(input_event_buffer)) < 0) {
    fatal_error("write key up");
  }

  input_event_buffer.type = EV_SYN;
  input_event_buffer.code = SYN_REPORT;
  input_event_buffer.value = 0;
  if (write(uinput_fd, &input_event_buffer, sizeof(input_event_buffer)) < 0) {
    fatal_error("write syn");
  }

  usleep(300 * 1000);
  ioctl(uinput_fd, UI_DEV_DESTROY);
  close(uinput_fd);

  return 0;
}
