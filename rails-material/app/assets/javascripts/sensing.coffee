# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/
#= require papaparse.min
#= require moment
#= require paper
#= require jquery-ui/core
#= require jquery-ui/widget
#= require jquery-ui/position
#= require jquery-ui/widgets/mouse
#= require jquery-ui/widgets/draggable
#= require jquery-ui/widgets/droppable
#= require jquery-ui/widgets/resizable
#= require jquery-ui/widgets/selectable
#= require jquery-ui/widgets/sortable
#= require viz
#= require viz/timeline



window.manifest = null
window.color_scheme = ["red","orange","blue","green","yellow","violet","purple","teal", "pink","brown","grey","black"]
window.data_source = "/data/compiled.json"

$ ->
	
	window.env = new VizEnvironment
		reposition_video: ()->
			pt = paper.project.getItem({name: "legend"}).bounds.bottomLeft
			$('#video-container').css
				top: pt.y + 30
				left: pt.x + 20
		ready: ()->
			scope = this
			$('.panel').draggable()
			@reposition_video()
			$(window).resize ()->
				scope.reposition_video()
			$("canvas").on 'wheel', (e)->
				delta = e.originalEvent.deltaY
				pt = paper.view.viewToProject(new paper.Point(e.originalEvent.offsetX, e.originalEvent.offsetY))
				e = _.extend e, 
					point: pt
					delta: new paper.Point(e.originalEvent.deltaX, e.originalEvent.deltaY)
				
				hits = _.filter paper.project.getItems({data: {class: "Timeline"}}), (el)->
					return el.contains(pt)
				_.each hits, (el)-> el.emit "mousedrag", e
			$('video').on 'loadeddata', (e)->
				_.each Timeline.lines, (line)->
					line.ui.video = this
					line.ui.range.timestamp = Timeline.ts
					line.refresh()	
			paper.tool = new paper.Tool
				video: $('video')[0]
				onKeyDown: (e)->
					switch e.key
						when "space"
							if this.video.paused then this.video.play() else this.video.pause()
	
window.exportSVG = ()->
	exp = paper.project.exportSVG
    asString: true
    precision: 5
  saveAs(new Blob([exp], {type:"application/svg+xml"}), participant_id+"_heater" + ".svg");

  	
class VizEnvironment
	constructor: (op)->
		_.extend this, op
		this.viz_settings = 
			padding: 30
			plot:
				height: 30
				width: 500
			colors: 
				0: "red"
				1: "green"
				2: "blue"
			render_iron_imu: false
			render_codes: true
		@acquireManifest(@renderData)
		
	renderData: (data)->
		window.installPaper()
		@makeLegend(data)
		
		this.timeline = new Timeline
			anchor: 
				pivot: "center"
				position: paper.view.bounds.center.add(new paper.Point(0, 300))
			controls: 
				rate: true
		Timeline.load data.activity.cesar.env.video
		this.codeline = new CodeTimeline
			title: "CODES"
			anchor: 
				pivot: "bottomCenter"
				position: this.timeline.ui.bounds.topCenter.add(new paper.Point(0, -25))
			controls: 
				rate: false

		this.sensorline = new SensorTimeline
			title: "SENSOR"
			anchor: 
				pivot: "bottomCenter"
				position: this.codeline.ui.bounds.topCenter.add(new paper.Point(0, -50))
			controls: 
				rate: false

		@makeTracks(data)
		@ready()

	


	makeTracks: (data)->
		scope = this
		# LEGEND CREATION
		g = new AlignmentGroup
			name: "users"
			title: 
				content: "SESSIONS"
			moveable: true
			padding: 5
			orientation: "vertical"
			background: 
				fillColor: "white"
				padding: 5
				radius: 5
				shadowBlur: 5
				shadowColor: new paper.Color(0.9)
			anchor: 
				pivot: "topLeft"
				position: paper.view.bounds.topLeft.add(new paper.Point(5, 430))
		g.init()


		_.each data.activity, (data, user)->
			
			label = new LabelGroup
				orientation: "horizontal"
				padding: 5
				text: user
				onMouseDown: (e)->
					Timeline.load data.env.video
					if codes = data.env.video.codes
						if scope.codeline
							scope.codeline.load codes
					if iron_acc = data.iron.imu.G
						if scope.sensorline
							scope.sensorline.load iron_acc

			g.pushItem label
	makeLegend: (data)->		
		# LEGEND CREATION
		g = new AlignmentGroup
			name: "legend"
			title: 
				content: "ACTORS"
			moveable: true
			padding: 5
			orientation: "horizontal"
			background: 
				fillColor: "white"
				padding: 5
				radius: 5
				shadowBlur: 5
				shadowColor: new paper.Color(0.9)
			anchor: 
				position: paper.view.bounds.topCenter.add(new paper.Point(0, this.viz_settings.padding))
		g.init()

		_.each data.actors, (color, actor)->
			color_code = new paper.Color color
			color_code.saturation = 0.8
		
			label = new LabelGroup
				orientation: "horizontal"
				padding: 5
				key: new paper.Path.Circle
					name: actor
					radius: 10
					fillColor: color_code
					data: 
						actor: true
						color: color
				text: actor
				data:
					activate: true
				update: ()->
					codes = paper.project.getItems
						name: "tag"
						data: 
							actor: actor
					if this.data.activate 
						this.opacity = 1 
						_.each codes, (c)-> c.visible = true
					else 
						this.opacity = 0.2
						_.each codes, (c)-> c.visible = false
				onMouseDown: ()->
					this.data.activate = not this.data.activate
					this.update()
			g.pushItem label


	
	mapEach: (root, mapFn)->
		scope = this
		root = mapFn(root)
		_.map root, (data, root)-> 
			if _.isObject(data) then scope.mapEach(data, mapFn)
	acquireManifest: (callbackFn)->
		scope = this
		rtn = $.getJSON data_source, (manifest)-> 
			window.manifest = manifest

			# RESOLVE JSON FILES
			scope.mapEach manifest, (obj)->
				if not obj.url then return obj
				filetype = obj.url.split('.').slice(-1)[0] 
				switch filetype
					when "json"
						return _.extend obj, 
							data: $.ajax({dataType: "json", url: obj.url, async: false}).responseJSON
					else
						return obj
			
			# ZIP adjustment
			_.each manifest, (data, user)->
				if data.iron.imu
					manifest[user].iron.imu = data.iron.imu.various.data


			# EXTRACT AUTHORS
			actors = _.values manifest
			actors = _.pluck actors, "env"
			actors = _.flatten _.pluck actors, "video"
			actors = _.flatten _.pluck actors, "codes"
			actors = _.flatten _.pluck actors, "data"
			actors = _.unique _.pluck actors, "actor"
			actors = _.object _.map actors, (a, i)-> 
				[a, color_scheme[i]]

			# console.log "actors", actors
			
			# ATTACH COLOR
			_.each manifest, (data, user)->
				manifest[user].env.video.codes.data = _.map data.env.video.codes.data, (code)->
					_.extend code, 
						color: actors[code.actor]
	
			callbackFn.apply scope, [
				activity: manifest
				actors: actors
			]

