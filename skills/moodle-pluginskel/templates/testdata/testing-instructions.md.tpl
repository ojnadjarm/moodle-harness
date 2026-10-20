# Testing {{component}}: <what is being tested, one line>

## Steps

1. Create a course with completion enabled: `/course/edit.php?category=<categoryid>`.
2. Add a Page to section 0: `/course/modedit.php?add=page&course=<courseid>&section=0`.
3. Create a teacher and a student: `/user/editadvanced.php?id=-1`.
4. Enrol them (Teacher, Student): `/user/index.php?id=<courseid>`.
5. <Configure the feature>: `<url>`.
6. <Exercise the feature>: `<url>`.

## Expected

- <result>

## Notes

- <non-obvious row, environment-dependent result or platform behaviour; one line each, or delete this section>

## Shortcut

`php {{dir}}/setup.php` builds steps 1-4 and seeds {{rows}} marked rows per plugin table (prints IDs, URLs and row counts); `php {{dir}}/reset.php` returns the scenario to its start state.
