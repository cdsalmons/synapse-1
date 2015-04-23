Synapse
=======

This repository contains the code used in the following paper:

[![Synapse: A Microservices Architecture for Heterogeneous-Database Web Applications](http://i.imgur.com/8IJjJB5.jpg)](http://viennot.com/synapse.pdf)

The paper can be downloaded here: [http://viennot.com/synapse.pdf](http://viennot.com/synapse.pdf)

The slides can be found here: [http://viennot.com/synapse-slides.pdf](http://viennot.com/synapse-slides.pdf)

The slides with speaker notes can be found here: [http://viennot.com/synapse-slides-notes.pdf](http://viennot.com/synapse-slides-notes.pdf)

The code
--------

Synapse was renamed from the original name Promiscuous, but in the code, the original name remains.

Synapse's behavior is specified in its test suite:
[./spec/integration](https://github.com/nviennot/synapse/tree/master/spec/integration).

If you are curious about the publishing algorithm, most of it is in here:
[./lib/promiscuous/publisher/operation/base.rb](https://github.com/nviennot/synapse/blob/master/lib/promiscuous/publisher/operation/base.rb).

Rails Quick Tutorial
--------------------

### 1. Preparation

We need a few things for the synapse tutorial:

* The AMQP broker [RabbitMQ](http://www.rabbitmq.com/) up and running.
* The key-value storage system [Redis](http://redis.io/) (at least 2.6) up and running.
* Both applications must be running on separate databases.
* Both applications must have a User model with two attributes name and email.

### 2. Publishing

By including the Promiscuous publisher mixin, we can publish the model attributes:

```ruby
# app/models/user.rb on the publisher app
class User
  include Promiscuous::Publisher
  publish :name, :email
end
```

### 3. Subscribing

Similarly to the publisher app, we can subscribe to the attributes:

```ruby
# app/models/user.rb on the subscriber app
class User
  include Promiscuous::Subscriber
  subscribe :name, :email

  after_create { Rails.logger.info "Hi #{name}!" }
end
```

### 4. Replication

The subscriber must listen for new data to arrive. Launch the subscriber with
the following command:

```
bundle exec promiscuous subscribe
```

You should start the subscriber *first*, otherwise the appropriate queues
will not be created. From now on, you should see the queue in the RabbitMQ
web admin page. Create a new user in the publisher's Rails console with:

```ruby
User.create(:name => 'Yoda')`
```

You should see the message "Hi Yoda!" appearing in the log file of the subscriber.


License
=======

LGPL.
