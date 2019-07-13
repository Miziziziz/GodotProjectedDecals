extends ImmediateGeometry

onready var area = $Area

const Z_BUFFER_DIS = 0.01 
const MIN_ANGLE = 0.0 #scale of 1.0 to 0.0
var frame_count = 0
func _physics_process(delta):
	frame_count += 1
	if frame_count != 3: #takes 2 frames to load colliders in area for some reason
		return
	perform_projection()

func perform_projection():
	init_planes()
	var bodies = area.get_overlapping_bodies()
	for body in bodies:
		var parent = body.get_parent()
		if "mesh" in parent:
			if parent.mesh.get_surface_count() == 0:
				continue
			var arrays = parent.mesh.surface_get_arrays(0)
			# if does not have array indices defined, create our own
			if arrays[ArrayMesh.ARRAY_INDEX] == null:
				if arrays[ArrayMesh.ARRAY_VERTEX].size() % 3 != 0: # if vertices not divisable by 3, ignore this mesh
					continue
				arrays[ArrayMesh.ARRAY_INDEX] = range(arrays[ArrayMesh.ARRAY_VERTEX].size())
			
			add_surfaces(parent, arrays[ArrayMesh.ARRAY_VERTEX], arrays[ArrayMesh.ARRAY_NORMAL], arrays[ArrayMesh.ARRAY_INDEX])
			#parent.hide()
	render_surfaces()

var all_norms = []
var all_verts = []
var verts_to_norms = {}
func add_surfaces(base, vertices, normals, indices):
	#print("vertices", vertices)
	#print("normals", normals)
	#print("indices", indices)
	var dir = global_transform.basis.z
	for i in range(0, indices.size(), 3):
		#convert normal to global direction
		#var normal = base.to_global(normals[indices[i]]) - base.global_transform.origin
		var normal = normal_to_new_base(base, self, normals[indices[i]])
		# if pointing towards us, duplicate it
		if normal.dot(Vector3.FORWARD) > MIN_ANGLE:
			all_verts.append(point_to_new_base(base, self, vertices[indices[i]]))
			all_verts.append(point_to_new_base(base, self, vertices[indices[i+1]]))
			all_verts.append(point_to_new_base(base, self, vertices[indices[i+2]]))
			all_norms.append(normal_to_new_base(base, self, normals[indices[i]]))
			all_norms.append(normal_to_new_base(base, self, normals[indices[i+1]]))
			all_norms.append(normal_to_new_base(base, self, normals[indices[i+2]]))
	push_out_verts()

func push_out_verts():
	#compile all normals corresponding to each vertice, since there are many duplicates
	for i in range(all_verts.size()):
		var ind = vec3_to_index(all_verts[i])
		if not ind in verts_to_norms:
			verts_to_norms[ind] = {}
		var n = all_norms[i]
		var n_ind = vec3_to_index(n)
		verts_to_norms[ind][n_ind] = n
	
	#push the vertices along their normals to prevent zfighting with existing geometry
	for i in range(all_verts.size()):
		var ind = vec3_to_index(all_verts[i])
		var norms = verts_to_norms[ind].values()
		var sum_of_normals = Vector3()
		for norm in norms:
			sum_of_normals += norm
		sum_of_normals /= norms.size() #normalize it
		all_verts[i] += sum_of_normals * Z_BUFFER_DIS #push out the vert

func normal_to_new_base(from_base, to_base, norm):
	var global = from_base.to_global(norm) - from_base.global_transform.origin
	return to_base.to_local(global + to_base.global_transform.origin)

func point_to_new_base(from_base, to_base, vert):
	return to_base.to_local(from_base.to_global(vert))

func render_surfaces():
	clear()
	begin(Mesh.PRIMITIVE_TRIANGLES)
	#begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(0, all_verts.size(), 3):
		
		var vert0 = all_verts[i]
		var vert1 = all_verts[i+1]
		var vert2 = all_verts[i+2]
		var vc = verts_in_area(vert0, vert1, vert2)
		if vc == 3:
			set_normal(all_norms[i])
			set_uv(get_uv_from_vert(all_verts[i]))
			add_vertex(all_verts[i])
			set_normal(all_norms[i+1])
			set_uv(get_uv_from_vert(all_verts[i+1]))
			add_vertex(all_verts[i+1])
			set_normal(all_norms[i+2])
			set_uv(get_uv_from_vert(all_verts[i+2]))
			add_vertex(all_verts[i+2])
		elif vc != 0 or area_overlaps_tri(vert0, vert1, vert2):
			var clipped_verts = clip_tri_to_area(PoolVector3Array([all_verts[i], all_verts[i+1], all_verts[i+2]]))
			clipped_verts = double_check_clipped_tris(clipped_verts)
			for v in clipped_verts:
				set_normal(all_norms[i])
				set_uv(get_uv_from_vert(v))
				add_vertex(v)
	end()

func get_uv_from_vert(vert):
	var uv = Vector2()
	uv.x = vert.x / to_local(area.to_global(Vector3.RIGHT)).x
	uv.y = vert.y / to_local(area.to_global(Vector3.DOWN)).y
	uv = (uv / 2.0) + Vector2(0.5, 0.5)
	uv.x = clamp(uv.x, 0.0, 1.0)
	uv.y = clamp(uv.y, 0.0, 1.0)
	return uv

func verts_in_area(vert0, vert1, vert2):
	var num_of_verts_in_area = 0
	if area_contains_vert(vert0):
		num_of_verts_in_area += 1
	if area_contains_vert(vert1):
		num_of_verts_in_area += 1
	if area_contains_vert(vert2):
		num_of_verts_in_area += 1
	return num_of_verts_in_area

func area_contains_vert(vert):
	var fwd = point_to_new_base(area, self, Vector3.BACK) * 2 #forward is negative for some reason
	var right = point_to_new_base(area, self, Vector3.RIGHT)
	var up = point_to_new_base(area, self, Vector3.UP)
	
	var is_in = vert.z > 0 and vert.z < fwd.z
	is_in = is_in and abs(vert.x) < right.x
	is_in = is_in and abs(vert.y) < up.y
	return is_in
	
	#print("vert:", vert, "scale: ", area.scale)
	#return vert.z > 0 and vert.z < area.scale.z and abs(vert.x) < area.scale.x and abs(vert.y) < area.scale.y

func area_overlaps_tri(vert0, vert1, vert2):
	#check for a triangle overlap by 1, raycast between all points in box area, and 2, raycast between all tri points
	var front = to_local(area.to_global(Vector3.BACK)) * 2
	var back = Vector3()
	var right = to_local(area.to_global(Vector3.RIGHT))
	var left = to_local(area.to_global(Vector3.LEFT))
	var top = to_local(area.to_global(Vector3.UP))
	var bot = to_local(area.to_global(Vector3.DOWN))
	
	var ftr = front + top + right
	var ftl = front + top + left
	var fbr = front + bot + right
	var fbl = front + bot + left
	
	var btr = back + top + right
	var btl = back + top + left
	var bbr = back + bot + right
	var bbl = back + bot + left
	
	var point_pairs = []
	point_pairs.append([btr, ftr])
	point_pairs.append([btl, ftl])
	point_pairs.append([bbr, fbr])
	point_pairs.append([bbl, fbl])
	point_pairs.append([ftl, ftr])
	point_pairs.append([fbl, fbr])
	point_pairs.append([btl, btr])
	point_pairs.append([bbl, bbr])
	point_pairs.append([ftr, fbr])
	point_pairs.append([ftl, fbl])
	point_pairs.append([btr, bbr])
	point_pairs.append([btl, bbl])
	for point_pair in point_pairs:
		if Geometry.segment_intersects_triangle(point_pair[0], point_pair[1], vert0, vert1, vert2):
			return true
	
	#check if sides of tri intersect area
	if Geometry.segment_intersects_convex(vert0, vert1, planes).size() != 0:
		return true
	if Geometry.segment_intersects_convex(vert1, vert2, planes).size() != 0:
		return true
	if Geometry.segment_intersects_convex(vert0, vert2, planes).size() != 0:
		return true
	
	return false

func clip_tri_to_area(tri_arr):
	var clip_buffer = []
	for plane in planes:
		var tmp_arr = Geometry.clip_polygon(tri_arr, plane)
		if tmp_arr.size() == 3:
			tri_arr = tmp_arr
		if tmp_arr.size() == 4:
			clip_buffer.append(PoolVector3Array([tmp_arr[0],tmp_arr[2],tmp_arr[3]]))
			tmp_arr.resize(3)
			tri_arr = tmp_arr
	for tri in clip_buffer:
		tri_arr.append_array(clip_tri_to_area(tri))
	return tri_arr

func double_check_clipped_tris(tri_arr):
	#sometimes clipping bugs out and returns tris outside area, this prevents that
	var clipped_verts = []
	if tri_arr.size() % 3 != 0: 
		return PoolVector3Array([])
	for i in range(0, tri_arr.size(), 3):
		var is_in = true
		for j in range(3):
			var vert = tri_arr[i+j]
			var tmp_vert = vert * 0.999 #move it slightly closer to the center to make it is correctly check if it's inside
			if tmp_vert.z < 0:
				tmp_vert.z += 0.01
			if !area_contains_vert(tmp_vert):
				is_in = false
		if is_in:
			clipped_verts.append(tri_arr[i])
			clipped_verts.append(tri_arr[i+1])
			clipped_verts.append(tri_arr[i+2])
	return PoolVector3Array(clipped_verts)

var planes = []
func init_planes():
	planes = []
	planes.append(Plane(Vector3.BACK, to_local(area.to_global(Vector3.BACK * 2)).length()))
	planes.append(Plane(Vector3.FORWARD, to_local(area.global_transform.origin).length()))
	planes.append(Plane(Vector3.RIGHT, to_local(area.to_global(Vector3.RIGHT)).length()))
	planes.append(Plane(Vector3.LEFT, to_local(area.to_global(Vector3.LEFT)).length()))
	planes.append(Plane(Vector3.UP, to_local(area.to_global(Vector3.UP)).length()))
	planes.append(Plane(Vector3.DOWN, to_local(area.to_global(Vector3.DOWN)).length()))

func vec3_to_index(v3):
	var round_amnt = 1000
	return "(" + str(int(v3.x * round_amnt)) + "," + str(int(v3.y * round_amnt)) + "," + str(int(v3.z * round_amnt)) + ")"