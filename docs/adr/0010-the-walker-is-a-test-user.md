# The walker is a test user

The walker gets the plan's UI walks, the pass rule for each, a Sandbox id, and where to open the app. It never reads or changes the code. It reports what passed and what broke, with a video and a screenshot. The skill, not the builder and not the walker, sorts each failure: a bug in the app goes to the builder, and a wrong walk is fixed in the plan, with a big change going to the user. A walker that reads the code tests what the code says, not what a user sees. A builder that gets every failure changes good code to match a walk the plan got wrong.
