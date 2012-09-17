inspect = require('eyes').inspector();

awssum = require('awssum');
amazon = awssum.load('amazon/amazon');
Swf = awssum.load('amazon/swf').Swf;

DecisionResponse = require("./models/DecisionResponse").DecisionResponse

createApplication = (options) ->
	app = new Application(options)
	return app


class Application
	constructor: (options)->
		# Check the options and define the default values 
		options ?= {}
		@options = options
		@options.force ?= false
		@options.accessKeyId ?= "BAD_KEY"
		@options.secretAccessKey ?= "BAD_SECRET_KEY"
		@options.region ?= "us-east-1"
		@options.domain ?= "sample-domain"
		@options.name ?= "sample-workflow"
		@options.decider ?= {}
		@options.decider.name ?= "#{@options.domain}-#{@options.name}-decider"
		@options.decider.taskList ?= () =>
			"#{@options.domain}-#{@options.name}-decider-default-tasklist"
		@options.decider.routes = [];
		@options.activities = [];

		@configStatus = 0;

		swfCfg = 
		    'accessKeyId' : @options.accessKeyId
		    'secretAccessKey' : @options.secretAccessKey
		    'region' : @options.region

		@swf = new Swf swfCfg
		winston = require 'winston'
		@logger = new (winston.Logger)({
    		transports: [
      			new (winston.transports.Console)({'colorize':true})
    		]
		});

	useActivity: (name, activityFn)->
		@options.activities.push {"name":name, "taskList": "#{name}-default-tasklist", "activityTask": activityFn}

	makeDecision: (route, decisionFn)->
		@options.decider.routes.push {"route":route, "decisionTask": decisionFn}

	start: (inputValue)->
		@_checkConfig ()=>
			inputValue ?= ""
			if typeof inputValue isnt "string"
				inputValue = "" + JSON.stringify inputValue
			swfCfg = 
				"Domain": @options.domain,
				"WorkflowId": @options.name+"-"+((Math.random()+"").substr(2)),
				"WorkflowType": {"name": @options.name, "version": "1.0"},
				"Input": inputValue
			@swf.StartWorkflowExecution swfCfg, (err, data)=>
				@logger.error "Unexpected error starting workflow", err if err?
				@logger.info "Started workflow execution with the following id: #{swfCfg.WorkflowId}" if data?


	listen: ()->
		@_checkConfig ()=>
			@_startListeners()

	_checkConfig: (callBack) ->
		@configStatus ?= 0

		return (callBack()) if @configStatus is 2

		return (setTimeout ()=>
			@_checkConfig callBack
		, 1000) if @configStatus is 1

		if @configStatus is 0
			@configStatus = 1
			@logger.info "Checking config, please wait..."
			_checkDomain @swf, @options.domain, @options.force, (err, data)=>
				if err?
					@configStatus = 0
					@logger.error err.message, err.context
				else
					@logger.info "Domain #{@options.domain} checked!"
					_checkWorkflow @swf, @options.domain, @options.name, @options.decider.taskList(), @options.force, (errD, dataD)=>
						if errD?
							@configStatus = 0
							@logger.error errD.message, errD.context
						else
							@logger.info "Workflow #{@options.name} checked!"
							func = (e, d)=>
								if e?
									@configStatus = 0
									@logger.error e.message, e.context
								else
									i++
									@logger.info "Activity #{@options.activities[i-1].name} checked!" if i>0
									if @options.activities[i]?
										_checkActivity @swf, @options.domain, @options.activities[i].name, @options.activities[i].taskList, @options.force, func
									else
										@configStatus = 2
										callBack()
							i=-1
							func()


	_startListeners: ()->
		@logger.info "Workflow application #{@options.domain}/#{@options.name} listening..."
		@_listenForActivity @options.activities[activ].name, @options.activities[activ].taskList for activ of @options.activities
		@_listen()

	_listenForActivity: (name, taskList)->
		@logger.info "Polling for next activity task (#{taskList})"

		swfCfg = 
			'Domain': @options.domain
			'TaskList': 
				"name": taskList

		@swf.PollForActivityTask swfCfg, (err, data)=>
			if err?
				@logger.error "Unexpected Error", err
			else
				body = data.Body
				token = body.taskToken
				if not token?
					@logger.info "No activity task in the pipe for #{taskList}, repolling..."
					process.nextTick ()=>@poll()
				else
					inspect data, "activity Data"
			process.nextTick ()=>
				@_listenForActivity name, taskList

	_listen: ()->
		@logger.info "Polling for next decision task (tasklist: #{@options.decider.taskList()})"

		swfCfg = 
			'Domain': @options.domain,
			'TaskList': 
				'name': "#{@options.decider.taskList()}"
		@swf.PollForDecisionTask swfCfg, (err, data)=>
			if err?
				@logger.error "Error polling decision task", err
			else
				body = data.Body
				token = body.taskToken

				if token?
					@logger.info "New decision task received"
					
					_makeRoute body.events, (routeError, request)=>
						response = new DecisionResponse(@, token)

						# Now find the route that fits our request:
						(
							if @options.decider.routes[tmpRoute].route is request.url
								@logger.debug "Making following decision: #{@options.decider.routes[tmpRoute].route}"
								@options.decider.routes[tmpRoute].decisionTask request, response
							else
							 @logger.debug "#{@options.decider.routes[tmpRoute].route} is not #{request.url}"
						) for tmpRoute of @options.decider.routes
						#@logger.debug route, request


			# Continue Polling anyway
			process.nextTick ()=>@_listen()

		

_makeRoute = (events, callBack) ->
	events ?= []
	request = {}
	response = {}
	route = ""
	#for (i=0; i<events.length; i++) 
	(
		handled = false
		if events[event].eventType is "WorkflowExecutionStarted"
			handled = true
			if route.indexOf("/start") < 0
				route += "/start"
				request = 
					workFlow:
						name: events[event].workflowExecutionStartedEventAttributes.workflowType.name
						version: events[event].workflowExecutionStartedEventAttributes.workflowType.version
						input: ""
					decisionTask:
						name:""
						status:"NONE"
				try
					request.workFlow.input = JSON.parse(events[event].workflowExecutionStartedEventAttributes.input)
				catch e
					request.workFlow.input = events[event].workflowExecutionStartedEventAttributes.input ? {}


		if events[event].eventType is "DecisionTaskScheduled"
			handled = true
			request.decisionTask.name = events[event].decisionTaskScheduledEventAttributes.taskList.name
			request.decisionTask.status = "SCHEDULED"

		if events[event].eventType is "DecisionTaskStarted"
			handled = true
			request.decisionTask.status = "STARTED"

		if events[event].eventType is "DecisionTaskTimedOut"
			handled = true
			request.decisionTask.status = "TIMED_OUT"

		if handled isnt true
			inspect events[event], "Evenement #{events[event].name}"
			throw "Unhandled event type : #{events[event].eventType}"

	) for event of events
	request.url = route
	callBack null, request

_checkDomain = (swf, domainName, force, callBack) ->
	force ?= false
	#check domain existence
	swfParams = 
		Name: domainName
	swf.DescribeDomain swfParams, (descDomainErr, descDomainData) =>
		if descDomainErr?
			if descDomainErr.Body? and descDomainErr.Body.__type? and descDomainErr.Body.__type.indexOf("UnknownResourceFault") > -1
				if !force
					#@logger.warn "Domain #{@options.domain} doesnt exist. Please use the force option to create it."
					callBack {err:"NO_DOMAIN", message:"Domain #{domainName} doesnt exist. Please use the force option to create it."}
				else
					swfParams = 
					    'Name': domainName,
					    'WorkflowExecutionRetentionPeriodInDays': '1'
					swf.RegisterDomain swfParams, (regDomainErr, regDomainData)->
						if regDomainErr?
							callBack {err:"UNEXPECTED", message:"Unexpected error encountered", context:regDomainErr}
						else
							callBack null, domainName
			else
				callBack {err:"UNEXPECTED", message:"Unexpected error encountered", context:descDomainErr}
		else
			callBack null, domainName

_checkWorkflow = (swf, domainName, workflowName, taskList, force, callBack) ->
	force ?= false
	#check domain existence
	swfParams = 
		Domain: domainName
		WorkflowType: 
			name: workflowName
			version: "1.0"
	swf.DescribeWorkflowType swfParams, (descWflErr, descWflData) =>
		if descWflErr?
			if descWflErr.Body? and descWflErr.Body.__type? and descWflErr.Body.__type.indexOf("UnknownResourceFault") > -1
				if !force
					#@logger.warn "Domain #{@options.domain} doesnt exist. Please use the force option to create it."
					callBack {err:"NO_WORKFLOW", message:"Workflow #{domainName}/#{workflowName} doesnt exist. Please use the force option to create it."}
				else
					swfParams = 
						"Domain": domainName,
						"Name": workflowName,
						"Version": "1.0",
						"Description": "Automatically created workflow type.",
						"DefaultTaskStartToCloseTimeout": "600",
						"DefaultExecutionStartToCloseTimeout": "3600",
						"DefaultTaskList": {"name": "#{taskList}"},
						"DefaultChildPolicy": "TERMINATE"
					swf.RegisterWorkflowType swfParams, (regWflErr, regWflData)->
						if regWflErr?
							callBack {err:"UNEXPECTED", message:"Unexpected error encountered", context:regWflErr}
						else
							callBack null, workflowName
			else
				callBack {err:"UNEXPECTED", message:"Unexpected error encountered", context:descWflErr}
		else
			callBack null, workflowName

_checkActivity = (swf, domainName, activityName, taskList, force, callBack) ->
	force ?= false
	#check domain existence
	swfParams = 
		Domain: domainName
		ActivityType: 
			name: activityName
			version: "1.0"
	swf.DescribeActivityType swfParams, (descActErr, descActData) =>
		if descActErr?
			if descActErr.Body? and descActErr.Body.__type? and descActErr.Body.__type.indexOf("UnknownResourceFault") > -1
				if !force
					callBack {err:"NO_ACTIVITY", message:"Activity #{domainName}/#{activityName} doesnt exist. Please use the force option to create it."}
				else
					swfParams = 
						"Domain": domainName
						"Name": activityName
						"Version": "1.0"
						"Description": "Automatically created activity type"
						"DefaultTaskStartToCloseTimeout": "600"
						"DefaultTaskHeartbeatTimeout": "120"
						"DefaultTaskList": 
							"name": taskList
						"DefaultTaskScheduleToStartTimeout": "300"
						"DefaultTaskScheduleToCloseTimeout": "900"
					swf.RegisterActivityType swfParams, (regActErr, regActData)->
						if regActErr?
							callBack {err:"UNEXPECTED", message:"Unexpected error encountered", context:regActErr}
						else
							callBack null, activityName
			else
				callBack {err:"UNEXPECTED", message:"Unexpected error encountered", context:descActErr}
		else
			callBack null, activityName



module.exports = createApplication