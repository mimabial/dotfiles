import datetime, os, sys, tempfile
from icalendar import Calendar
from icalendar.prop import vDDDTypes

path, summary, priority = sys.argv[1:]
with open(path, "rb") as handle:
    calendar = Calendar.from_ical(handle.read())
task = calendar.walk("VTODO")[0]
if summary:
    task["SUMMARY"] = summary
if priority:
    task["PRIORITY"] = {"none": 0, "low": 9, "medium": 5, "high": 1}[priority]
now = vDDDTypes(datetime.datetime.now(datetime.timezone.utc))
task["DTSTAMP"], task["LAST-MODIFIED"] = now, now
task["SEQUENCE"] = int(task.get("SEQUENCE", 0)) + 1
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
try:
    with os.fdopen(fd, "wb") as handle:
        handle.write(calendar.to_ical())
    os.chmod(tmp, os.stat(path).st_mode)
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
