# The walks run as a test user

The Proof agent gets the plan's UI walks, the pass rule for each, and where to open the app. It does not read or change the app's code. It reports what passed and what broke, with a video and a screenshot. The skill, not the builder and not the Proof agent, sorts each failure: a bug in the app goes to the builder, and the skill fixes a wrong walk in the plan, with a big change going to the user. A tester that reads the code tests what the code says, not what a user sees. A builder that gets every failure changes good code to match a walk the plan got wrong.
