#!ruby

p "what we got here..."

# for debugging, drop the environment vars of the ruby process so we can see what to expect
ENV.each { |k,v| p k + ": " + v }

