# The Cursor create call on a Mac stops after 20 seconds

For a My Machines agent, Cursor's create call does not return until the whole run ends. `create_on_mac` in `cursor.sh` stops the call after 20 seconds and then finds the new agent by its worker's name, which no other agent has (#230).

A create call that waits for the whole run would hold the start step for the length of the run, and the watch could not start. A reply that comes back inside the 20 seconds is used as it is.
