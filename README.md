
# deviman

Example application in Janet programming language for discorvery and 
administration of simple network devices (arduinos, etc).

## Features

- Web application
- Only standart library and spork.
- No database, just pure Janet datastructures marshalled to file.
- Extensive use of `ev`.
- On frontend use htmx, missing and hyperscript.

## Development

To download development dependencies, I mean `spork`, run:

```
> jpm -l deps
```

To test the codebase run: 

```
> jpm -l test
```

To run the development server, run:

```
> jpm -l janet deviman/init.janet
```
  