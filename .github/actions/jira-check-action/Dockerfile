FROM ruby:3.1.2-slim

ARG JIRA_API_TOKEN=$JIRA_API_TOKEN
ARG JIRA_USER_NAME=$JIRA_USER_NAME

ENV JIRA_API_TOKEN=$JIRA_API_TOKEN
ENV JIRA_USER_NAME=$JIRA_USER_NAME

COPY ./program.rb /program.rb

ENTRYPOINT ["ruby", "/program.rb"]

