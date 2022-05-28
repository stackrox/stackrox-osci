FROM quay.io/centos/centos:stream8

RUN echo "I came from:" && cat /hello_world.txt || true
RUN echo "I am an image!" >> /hello_world.txt
