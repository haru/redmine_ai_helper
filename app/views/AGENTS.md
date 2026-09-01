# app/views Guidelines

## ERB / JavaScript Separation

JavaScript written inline in ERB templates must be limited to the minimal
code needed to bridge the ERB template and the JavaScript asset files.
Examples of what belongs inline in ERB:

- Attaching JS event handlers to DOM elements created in the ERB template.
- Passing Ruby variables to JavaScript.
- Building URL paths with Rails helpers and passing them to JavaScript.

All logic must live in JavaScript files under `assets/javascripts/`, not
inline in ERB.
