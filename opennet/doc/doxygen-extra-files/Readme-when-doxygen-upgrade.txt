# NOTE from MartinG (monomartin)

My aim is to have a table of content at the beginning of all pages. This toc should span over the whole page and not only on the right side, which is default configuration.

Configuration with newer version of doxygen--------------------

# insert following line in "doyyfile"
in doxyfile the attribute HTML_EXTRA_STYLESHEET is ignored.


Configuration with doxygen 1.8.1.2 which is installed on minato----------------

In doyyfile the attribute HTML_EXTRA_STYLESHEET is ignored.
Therefore extra css and html files are given. (header.html, footer.html and stylesheet.css)
