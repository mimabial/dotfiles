import os
import sys
import time

epoch, *command = sys.argv[1:]
wall_clock_timer = os.timerfd_create(time.CLOCK_REALTIME)
os.timerfd_settime(wall_clock_timer, flags=os.TFD_TIMER_ABSTIME, initial=float(epoch))
os.read(wall_clock_timer, 8)
os.execv(command[0], command)
