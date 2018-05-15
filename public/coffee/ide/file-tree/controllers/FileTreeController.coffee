define [
	"base"
], (App) ->
	App.controller "FileTreeController", ["$scope", "$modal", "ide", "$rootScope", ($scope, $modal, ide, $rootScope) ->
		$scope.openNewDocModal = () ->
			$modal.open(
				templateUrl: "newDocModalTemplate"
				controller:  "NewDocModalController"
				resolve: {
					parent_folder: () -> ide.fileTreeManager.getCurrentFolder()
				}
			)

		$scope.openNewFolderModal = () ->
			$modal.open(
				templateUrl: "newFolderModalTemplate"
				controller:  "NewFolderModalController"
				resolve: {
					parent_folder: () -> ide.fileTreeManager.getCurrentFolder()
				}
			)

		$scope.openUploadFileModal = () ->
			$modal.open(
				templateUrl: "uploadFileModalTemplate"
				controller:  "UploadFileModalController"
				scope: $scope
				resolve: {
					parent_folder: () -> ide.fileTreeManager.getCurrentFolder()
				}
			)

		$scope.openLinkedFileModal = window.openLinkedFileModal = () ->
			unless 'url' in window.data.enabledLinkedFileTypes
				console.warn("Url linked files are not enabled")
				return
			$modal.open(
				templateUrl: "linkedFileModalTemplate"
				controller:  "LinkedFileModalController"
				scope: $scope
				resolve: {
					parent_folder: () -> ide.fileTreeManager.getCurrentFolder()
				}
			)

		$scope.openProjectLinkedFileModal = window.openProjectLinkedFileModal = () ->
			unless 'url' in window.data.enabledLinkedFileTypes
				console.warn("Project linked files are not enabled")
				return
			$modal.open(
				templateUrl: "projectLinkedFileModalTemplate"
				controller:  "ProjectLinkedFileModalController"
				scope: $scope
				resolve: {
					parent_folder: () -> ide.fileTreeManager.getCurrentFolder()
				}
			)

		$scope.orderByFoldersFirst = (entity) ->
			return '0' if entity?.type == "folder"
			return '1'

		$scope.startRenamingSelected = () ->
			$scope.$broadcast "rename:selected"

		$scope.openDeleteModalForSelected = () ->
			$scope.$broadcast "delete:selected"
	]

	App.controller "NewDocModalController", [
		"$scope", "ide", "$modalInstance", "$timeout", "parent_folder",
		($scope,   ide,   $modalInstance,   $timeout,   parent_folder) ->
			$scope.inputs = 
				name: "name.tex"
			$scope.state =
				inflight: false

			$modalInstance.opened.then () ->
				$timeout () ->
					$scope.$broadcast "open"
				, 200

			$scope.create = () ->
				name = $scope.inputs.name
				if !name? or name.length == 0
					return
				$scope.state.inflight = true
				ide.fileTreeManager
					.createDoc(name, parent_folder)
					.then () ->
						$scope.state.inflight = false
						$modalInstance.close()
					.catch (response)->
						{ data } = response
						$scope.error = data
						$scope.state.inflight = false

			$scope.cancel = () ->
				$modalInstance.dismiss('cancel')
	]

	App.controller "NewFolderModalController", [
		"$scope", "ide", "$modalInstance", "$timeout", "parent_folder",
		($scope,   ide,   $modalInstance,   $timeout,   parent_folder) ->
			$scope.inputs = 
				name: "name"
			$scope.state =
				inflight: false

			$modalInstance.opened.then () ->
				$timeout () ->
					$scope.$broadcast "open"
				, 200

			$scope.create = () ->
				name = $scope.inputs.name
				if !name? or name.length == 0
					return
				$scope.state.inflight = true
				ide.fileTreeManager
					.createFolder(name, parent_folder)
					.then () ->
						$scope.state.inflight = false
						$modalInstance.close()
					.catch (response)->
						{ data } = response
						$scope.error = data
						$scope.state.inflight = false

			$scope.cancel = () ->
				$modalInstance.dismiss('cancel')
	]

	App.controller "UploadFileModalController", [
		"$scope", "$rootScope", "ide", "$modalInstance", "$timeout", "parent_folder", "$window"
		($scope,   $rootScope,   ide,   $modalInstance,   $timeout,   parent_folder, $window) ->
			$scope.parent_folder_id = parent_folder?.id
			$scope.tooManyFiles = false
			$scope.rateLimitHit = false
			$scope.secondsToRedirect = 10
			$scope.notLoggedIn = false
			$scope.conflicts = []
			$scope.control = {}

			needToLogBackIn = ->
				$scope.notLoggedIn = true
				decreseTimeout = ->
					$timeout (() ->
						if $scope.secondsToRedirect == 0
							$window.location.href = "/login?redir=/project/#{ide.project_id}"
						else
							decreseTimeout()
							$scope.secondsToRedirect = $scope.secondsToRedirect - 1
					), 1000

				decreseTimeout()

			$scope.max_files = 40
			$scope.onComplete = (error, name, response) ->
				$timeout (() ->
					uploadCount--
					if response.success
						$rootScope.$broadcast 'file:upload:complete', response
					if uploadCount == 0 and response? and response.success
						$modalInstance.close("done")
				), 250

			$scope.onValidateBatch = (files)->
				if files.length > $scope.max_files
					$timeout (() ->
						$scope.tooManyFiles = true
					), 1
					return false
				else
					return true

			$scope.onError = (id, name, reason)->
				console.log(id, name, reason)
				if reason.indexOf("429") != -1
					$scope.rateLimitHit = true
				else if reason.indexOf("403") != -1
					needToLogBackIn()

			_uploadTimer = null
			uploadIfNoConflicts = () ->
				if $scope.conflicts.length == 0
					$scope.doUpload()

			uploadCount = 0
			$scope.onSubmit = (id, name) ->
				uploadCount++
				if ide.fileTreeManager.existsInFolder($scope.parent_folder_id, name)
					$scope.conflicts.push name
					$scope.$apply()
				if !_uploadTimer?
					_uploadTimer = setTimeout () ->
						_uploadTimer = null
						uploadIfNoConflicts()
					, 0
				return true
			
			$scope.onCancel = (id, name) ->
				uploadCount--
				index = $scope.conflicts.indexOf(name)
				if index > -1
					$scope.conflicts.splice(index, 1)
				$scope.$apply()
				uploadIfNoConflicts()

			$scope.doUpload = () ->
				$scope.control?.q?.uploadStoredFiles()

			$scope.cancel = () ->
				$modalInstance.dismiss('cancel')
	]

	App.controller "ProjectLinkedFileModalController", [
		"$scope", "ide", "$modalInstance", "$timeout", "parent_folder",
		($scope,   ide,   $modalInstance,   $timeout,   parent_folder) ->
			$scope.data =
				projects: null # or []
				selectedProject: null
				projectEntities: null # or []
				selectedProjectEntity: null
			$scope.state =
				inFlight: false
				error: false

			$scope.$watch 'data.selectedProject', (newVal, oldVal) ->
				return if !newVal
				$scope.data.selectedProjectEntity = null
				$scope.getProjectEntities($scope.data.selectedProject)

			$scope._reset = () ->
				$scope.state.inFlight = false
				$scope.state.error = false

			$scope._resetAfterResponse = (opts) ->
				isError = !!opts.err
				$scope.state.inFlight = false
				$scope.state.error = isError

			$scope.shouldEnableProjectSelect = () ->
				state = $scope.state
				data = $scope.data
				return !state.inFlight && data.projects

			$scope.shouldEnableProjectEntitySelect = () ->
				state = $scope.state
				data = $scope.data
				return !state.inFlight && data.projects && data.selectedProject

			$scope.shouldEnableCreateButton = () ->
				state = $scope.state
				data = $scope.data
				return !state.inFlight &&
					data.projects &&
					data.selectedProject &&
					data.projectEntities &&
					data.selectedProjectEntity

			$scope.getUserProjects = () ->
				$scope.state.inFlight = true
				ide.$http.get("/user/projects", {
					_csrf: window.csrfToken
				})
				.then (resp) ->
					$scope.data.projectEntities = null
					$scope.data.projects = resp.data.projects
					$scope._resetAfterResponse(err: false)
				.catch (err) ->
					$scope._resetAfterResponse(err: true)

			$scope.getProjectEntities = (project_id) =>
				$scope.state.inFlight = true
				ide.$http.get("/project/#{project_id}/entities", {
					_csrf: window.csrfToken
				})
				.then (resp) ->
					if $scope.data.selectedProject == resp.data.project_id
						$scope.data.projectEntities = resp.data.entities
						$scope._resetAfterResponse(err: false)
				.catch (err) ->
					$scope._resetAfterResponse(err: true)

			# TODO: remove
			window._S = $scope

			$scope.init = () ->
				$scope.getUserProjects()
			$timeout($scope.init, 100)

			$scope.create = () ->
				console.log ">> create"

			$scope.cancel = () ->
				$modalInstance.dismiss('cancel')

	]

	# TODO: rename all this to UrlLinkedFilModalController
	App.controller "LinkedFileModalController", [
		"$scope", "ide", "$modalInstance", "$timeout", "parent_folder",
		($scope,   ide,   $modalInstance,   $timeout,   parent_folder) ->
			$scope.inputs =
				name: ""
				url: ""
			$scope.nameChangedByUser = false
			$scope.state =
				inflight: false

			$modalInstance.opened.then () ->
				$timeout () ->
					$scope.$broadcast "open"
				, 200

			$scope.$watch "inputs.url", (url) ->
				if url? and url != "" and !$scope.nameChangedByUser
					url = url.replace("://", "") # Ignore http:// etc
					parts = url.split("/").reverse()
					if parts.length > 1 # Wait for at one /
						$scope.inputs.name = parts[0]

			$scope.create = () ->
				{name, url} = $scope.inputs
				if !name? or name.length == 0
					return
				if !url? or url.length == 0
					return
				$scope.state.inflight = true
				ide.fileTreeManager
					.createLinkedFile(name, parent_folder, 'url', {url})
					.then () ->
						$scope.state.inflight = false
						$modalInstance.close()
					.catch (response)->
						{ data } = response
						$scope.error = data
						$scope.state.inflight = false

			$scope.cancel = () ->
				$modalInstance.dismiss('cancel')
	]
