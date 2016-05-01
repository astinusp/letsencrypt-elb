FROM ruby:latest

#VARIABLES

ENV dir /opt/letsencrypt_elb

# Prepare directory structure
RUN mkdir -p ${dir}/lib

# Copy Gemfile and update bundle
COPY Gemfile  ${dir}/Gemfile
RUN cd ${dir};bundler install

# Copy Application
COPY letsencrypt.rb ${dir}
COPY config.yaml ${dir}
COPY certs ${dir}/certs
COPY hooks ${dir}/hooks
COPY lib ${dir}/lib
COPY acme_key ${dir}/acme_key

WORKDIR ${dir}
CMD ruby ./letsencrypt.rb -d
