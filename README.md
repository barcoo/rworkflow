# Rworkflow

[![GitHub release](https://img.shields.io/badge/release-0.7.0-blue.png)](https://github.com/barcoo/rworkflow/releases/tag/0.7.0)
[![Build Status](https://travis-ci.org/barcoo/rworkflow.svg?branch=master&cache=busted)](https://travis-ci.org/barcoo/rworkflow)
[![Coverage Status](https://coveralls.io/repos/github/barcoo/rworkflow/badge.svg?branch=master)](https://coveralls.io/github/barcoo/rworkflow?branch=master)

The rworkflow framework removes many headaches when it comes to asynchronous tasks that need to run after the other, depending on their previous state.

A workflow is basically a set of defined states with transitions between them (a state machine or lifecycle) in which every state can contain a set of jobs (a job can be any serializable object). A set of jobs can then be pushed to the workflow on the initial state and then they can transit between the states following the transitions defined. Moreover, the jobs can be also transformed (e.g. a state receives 100 jobs, groups them into one unique job and then pushes this unique job to the next state with a transition).

A simple flow (Flow class) only implements this model, but there is a subclass of the simple flow (SidekiqFlow) which interprets every state of the lifecycle as a sidekiq job. Thus, whenever some jobs are pushed to the workflow, this dynamically creates the needed sidekiq workers to complete the workflow.


## Define a lifecycle

The lifecycle is the definition of the state machine that every job pushed to the workflow will transit:

```ruby
lifecycle = Workflow::Lifecycle.new do |lc|
  lc.state("Floating", {cardinality: 10}) do |state|
    state.transition :rescued, 'Lifeboat'
    state.transition :drowned, Flow::STATE_FAILED
  end

  lc.state("Lifeboat", {cardinality: 2}) do |state|
    state.transition :landed, 'Land'
    state.transition :starved, Flow::STATE_FAILED
  end

  lc.state("Land") do |state|
    state.transition :rescued, Flow::STATE_SUCCESSFUL
    state.transition :died, Flow::STATE_FAILED
  end

  lc.initial = "Floating"
end
```

Notes:

- For SidekiqFlow worflows the cycle state names need to be the same as an existing class that derives from Workflow::Worker (which implements a SidekiqWork)
- The transition state names (e.g. :rejected, :generated) are arbitrary, the Worker needs to call those later. There can be more than two.
- There are some predefined final states (Flow::STATE_FAILED, Flow::STATE_SUCCESSFUL). When all jobs are pushed via transitions to one of these states, the workflow is then finished.
- The state cardinality indicates how many jobs will be served to a state (by default one)

## Create Workers

For SidekiqFlow create a subclass of Workflow::Worker for each state defined on the lifecycle (except for predefined final states)

```ruby
class Floating < Workflow::Worker
  def process(objects)
    # The size of objects will be at the most the cardinality defined on the lifecycle
    rescued, drowned = objects.partition { |object| object.even? }

    transition(:rescued, rescued)
    transition(:drowned, drowned)
  end
end

class Lifeboat < Workflow::Worker
  def process(objects)
    landed, starved = objects.partition { |object| object < 4 }

    transition(:landed, landed)
    transition(:starved, starved)
  end
end

class Land < Workflow::Worker
  def process(objects)
    rescued, died = objects.partition { |object| object == 0 }

    transition(:rescued, rescued)
    transition(:died, died)
  end
end
```

Notes:

- Create a class with the exact name that you defined above in the lifecycle definition
- You will be given an array of objects of a size to a maximum of the defined cardinality in the state. By default is 1.
- The worker is responsible for the jobs that receives: it has to define a transition for them or otherwise they will be out of the workflow.

## Create and execute the Workflow

```ruby
options = {}
workflow = Workflow::SidekiqFlow.create(lifecycle, 'SafeBoatWorkflow', options)
initial_jobs = [1,2,3,45,6,7,8,9,10]
workflow.start(initial_jobs)
```

Notes:

- Create a new Sidekiq flow using the lifecycle object defined in the first step above
- Run flow.start passing in an array of objects
- The objects need to be serializable
- _options_ can contain several properties for the workflow (TODO: complete/expand)

# Roadmap

1. Decouple persistence layer (for now rworkflow depends on redis_rds which, in turn, depends on redis)
2. See [State and Transition Policies](doc/states_and_transitions_policies.rdoc).
3. Test Helper (simplify tests)
4. Improve logging
5. Use a separated Redis instance/db instead of a namespace?
6. sidekiq and rails dependencies should be optional
7. Move Web UI from CimRails to here
