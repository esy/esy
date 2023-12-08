---
id: website-and-docs
title: Website and documentation
---

Esy uses [docusaurus](https://docusaurus.io/). All the code for the website can be found in the [`site`](https://github.com/esy/esy/tree/master/site) folder on the esy github repository.

To make changes, clone the repository and `cd site/`. Then

1. Install the dependencies

  ```
  yarn # be sure be inside the site/ folder

  ```

2. Run site locally:

  ```
  yarn start
  ```

3. When you are happy with the changes, raise a PR and get it approved.

4. If you're an admin, you can wait for github actions to finish generating the HTML pages and fetch the `gh-pages` branch via git. You can then force push to [esy.github.io](https://github.com/esy/esy.github.io).

