#!/usr/bin/env python
import os.path
import sys
from sys import exit
import os
from pprint import pprint

def updatebosh(fname, newfile, mode):
	try:

		cpi_url = os.environ['BOSH_AZURE_CPI_URL']
		cpi_sha1 = os.environ['BOSH_AZURE_CPI_SHA1']
		if mode == 'performance':
			bosh_instance_type = os.environ['BOSH_AZURE_INSTANCE_TYPE']
			bosh_vm_storage_account = os.environ['BOSH_AZURE_VM_STORAGE_ACCOUNT']
			bosh_disk_size = os.environ['BOSH_AZURE_DISK_SIZE']
		stemcell_url = os.environ['BOSH_AZURE_STEMCELL_URL']
		stemcell_sha1 = os.environ['BOSH_AZURE_STEMCELL_SHA1']

		with open(fname) as f:
			l = f.readlines()

		print('updating cpi')
		# change cpi 
		for i in l:
			if 'name: bosh-azure-cpi' in i:
				node_index = l.index(i)
				
				# change cpi url
				if l[node_index + 1].strip().startswith('url:'):
					print('find url node for cpi, changing...')
					l[node_index + 1] = l[node_index + 1].replace(l[node_index + 1].split()[-1], cpi_url)
					print('done')
				else:
					print('cannot find cpi url node')
					raise ValueError
				# change cpi sha1
				if l[node_index + 2].strip().startswith('sha1:'):
					print('find sha1 node for cpi, changing...')
					l[node_index + 2] = l[node_index + 2].replace(l[node_index + 2].split()[-1], cpi_sha1)    
					print('done')
				else:
					print('cannot find cpi sha1 node')
					raise ValueError

			# update bosh vm
			if mode == 'performance':
				if 'instance_type' in i:
					node_index = l.index(i)
					print('updating bosh')
					if bosh_instance_type == '':
						print('keep current bosh instance type as default, no changing...')
					else:
						print('find instance_type node for bosh, changing...')
						l[node_index] = l[node_index].replace(l[node_index].split()[-1],bosh_instance_type)
						print('done')
					# insert storage account name node
					print('inserting storage_account_name node for bosh')
					char_start_index = l[node_index].index('instance_type')
					space_str = l[node_index][:char_start_index]
					storage = space_str + 'storage_account_name: ' + bosh_vm_storage_account + '\n'
					l.insert(node_index + 1, storage)
					print('inserting ephemeral_disk node and give disk size value for bosh')
					ephemeral_disk = space_str + 'ephemeral_disk:' + '\n'
					l.insert(node_index + 2, ephemeral_disk)
					disksize = space_str + ' '*2 + 'size: ' + bosh_disk_size + '\n' #indent
					l.insert(node_index + 3, disksize)
					print('done')

				else: 
					pass

		if stemcell_url != '' and stemcell_sha1 != '':
			print('updating stemcell for bosh')
			for i in l:
				if 'url' in i and 'https' in i and 'stemcell' in i:
					print('find stemcell node for bosh, changing...')
					node_index = l.index(i)
					l[node_index] = l[node_index].replace(l[node_index].split()[-1], stemcell_url)
					l[node_index + 1] = l[node_index + 1].replace(l[node_index + 1].split()[-1], stemcell_sha1)
					print('done')
					break

		with open(newfile, 'w') as f:
			f.writelines(l)
		#pprint(l)

		renameyaml(fname,newfile)

	except KeyError as e:
		print('get environ failed, key:{}'.format(e))
	except IOError as e:
		print('open file failed, err:{}'.format(e))
	except ValueError as e:
		print('get node failed, err:{}'.format(e))
	except Exception as e:
		print(e)
	else:
		print('update yaml config for bosh successfully')
		return True

def updatecf(fname, newfile, mode):
	try:
		if mode == 'performance':
			# get environment
			compile_instance_type = os.environ['BOSH_AZURE_COMPILE_INSTANCE_TYPE']
			compile_vm_storage_account = os.environ['BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT']
			compile_disk_size = os.environ['BOSH_AZURE_COMPILE_DISK_SIZE']
			cf_rp_small = os.environ['BOSH_AZURE_CF_RP_SMALL']
			cf_rp_medium = os.environ['BOSH_AZURE_CF_RP_MEDIUM']
			cf_rp_large = os.environ['BOSH_AZURE_CF_RP_LARGE']
			cf_rp_small_storage_account = os.environ['BOSH_AZURE_CF_RP_SMALL_STORAGE_ACCOUNT']
			cf_rp_medium_storage_account = os.environ['BOSH_AZURE_CF_RP_MEDIUM_STORAGE_ACCOUNT']
			cf_rp_large_storage_account = os.environ['BOSH_AZURE_CF_RP_LARGE_STORAGE_ACCOUNT']

			# dict of job-resource_pool 
			dict_job_rp = {
					"consul_z1": "small_z1",
					"ha_proxy_z1": "medium_z1",
					"nats_z1": "medium_z1",
					"nfs_z1": "medium_z1",
					"etcd_z1": "medium_z1",
					"postgres_z1": "medium_z1",
					"uaa_z1": "medium_z1",
					"api_z1": "large_z1",
					"hm9000_z1": "medium_z1",
					"runner_z1": "large_z1",
					"doppler_z1": "medium_z1",
					"loggregator_trafficcontroller_z1": "medium_z1",
					"router_z1": "medium_z1",
					"acceptance_tests": "medium_z1",
					"acceptance-tests-internetless": "medium_z1",
					"smoke_tests": "medium_z1",
			}
			
		stemcell_url = os.environ['BOSH_AZURE_STEMCELL_URL']
		stemcell_sha1 = os.environ['BOSH_AZURE_STEMCELL_SHA1']

		deploy_cf_sh_path = 'deploy_cloudfoundry.sh'

		with open(fname) as f:
			l = f.readlines()

		if mode == 'performance':
			for i in l:
				# update compile vm size
				if 'compilation' in i:
					print('updating compile')
					node_index = l.index(i)
					for ii in l[node_index:]:
						if 'instance_type' in ii:
							node_index = l.index(ii, node_index)
							if compile_instance_type == '':
								print('keep current compilation instance type as default, no changing...')
							else:
								print('find instance_type node for compile, changing...')
								l[node_index] = l[node_index].replace(l[node_index].split()[-1],compile_instance_type)
								print('done')
							break
					# get the space length for print
					print('inserting storage_account_name node for compile')
					char_start_index = l[node_index].index('instance_type')
					space_str = l[node_index][:char_start_index]
					storage = space_str + 'storage_account_name: ' + compile_vm_storage_account + '\n'
					# insert the storage acout name node
					l.insert(node_index + 1, storage)
					print('inserting ephemeral_disk node and give disk size value for compile')
					ephemeral_disk = space_str + 'ephemeral_disk:' + '\n'
					l.insert(node_index + 2, ephemeral_disk)
					disksize = space_str + ' '*2 + 'size: ' + compile_disk_size + '\n' #indent
					l.insert(node_index + 3, disksize)
					break
			
			# update resource pools
			l = updatecfresourcepools(l, cf_rp_small, cf_rp_small_storage_account,
				cf_rp_medium, cf_rp_medium_storage_account, cf_rp_large, cf_rp_large_storage_account)

			# update jobs
			for j, rp in dict_job_rp.iteritems():
				l = updatejobs(l, j, rp)

			with open(newfile,'w') as f:
				f.writelines(l)
			#pprint(l)

			renameyaml(fname,newfile)

		if stemcell_url != '' and stemcell_sha1 != '':
			print('updating stemcell for cf deployment')
			ver = stemcell_url.split('v=')[1]
			print('work with stemcell v{}'.format(ver))
			with open(deploy_cf_sh_path, 'r') as f:
				l = f.readlines()
			for i in l:
				if 'bosh upload stemcell http' in i:
					node_index = l.index(i)
					old_stemcell = i.split()[3]
					i = i.replace(old_stemcell, stemcell_url)
					l[node_index] = i
					break
			with open(deploy_cf_sh_path, 'w') as f:
				f.writelines(l)

	except KeyError as e:
		print('get environ failed, error: {}'.format(e))
	except IOError as e:
		print('open file failed, error: {}'.format(e))
	except ValueError as e:
		print('get node failed, error: {}'.format(e))
	except Exception as e:
		print(e)
	else:
		print('update yaml config for cf successfully')
		return True

def renameyaml(fname, newfile):
	# backup the original
	os.rename(fname, os.path.join(os.path.dirname(fname), os.path.basename(fname) + '.bak'))
	# rename the updated
	os.rename(newfile, fname)
	print('rename {} done'.format(fname))

def updatecfresourcepools(source_list, small_inst_type, small_storage, medium_inst_type, medium_storage, large_inst_type, large_storage):
	try:

		# content template
		content = '''resource_pools:
- name: small_z1
  network: cf_private
  stemcell:
    name: bosh-azure-hyperv-ubuntu-trusty-go_agent
    version: latest
  cloud_properties:
    instance_type: {}
    security_group: nsg-cf
    ephemeral_disk:
      size: 30_720
    storage_account_name: {}
  env:
    bosh:
      password: {}
- name: medium_z1
  network: cf_private
  stemcell:
    name: bosh-azure-hyperv-ubuntu-trusty-go_agent
    version: latest
  cloud_properties:
    instance_type: {}
    security_group: nsg-cf
    ephemeral_disk:
      size: 61_440
    storage_account_name: {}
  env:
    bosh:
      password: {}
- name: large_z1
  network: cf_private
  stemcell:
    name: bosh-azure-hyperv-ubuntu-trusty-go_agent
    version: latest
  cloud_properties:
    instance_type: {}
    security_group: nsg-cf
    ephemeral_disk:
      size: 102_400
    storage_account_name: {}
  env:
    bosh:
      password: {}
      '''
		for i,v in enumerate(source_list):
			if 'resource_pools:' in v:
				node_index_rp_start = i
			if 'compilation:' in v:
				node_index_rp_end = i - 1
		else:
			print('get start and end indexes for resource_pools done')

		# get bosh env password
		for i,v in enumerate(source_list[node_index_rp_start: node_index_rp_end]):
			if 'password' in v and ':' in v:
				bosh_pwd = source_list[node_index_rp_start: node_index_rp_end][i].split()[-1]
				break

		del source_list[node_index_rp_start: node_index_rp_end]
		# insert the new resource pools
		source_list.insert(node_index_rp_start, content.format(small_inst_type, small_storage, bosh_pwd, 
			medium_inst_type, medium_storage, bosh_pwd, 
			large_inst_type, large_storage, bosh_pwd))
		print('update resource_pools done')
		return source_list
	except Exception as e:
		print('update resource_pools failed, error: {}'.format(str(e)))

def updatejobs(source_list, job, resource_pool):
	try:
		for i,v in enumerate(source_list):
			if 'name' in v and ':' in v and job in v:
				print('found job: {}'.format(job))
				node_index_job_start = i
				break
		for i,v in enumerate(source_list[node_index_job_start:]):
			if 'resource_pool' in v and ':' in v and 'resource_z1' in v:
				node_index_target_rp = node_index_job_start + i
				break
		source_list[node_index_target_rp] = source_list[node_index_target_rp].replace(source_list[node_index_target_rp].split()[-1], resource_pool)
		print('resource pool changed to {} for job: {}'.format(resource_pool,job))
		return source_list
	except Exception as e:
		print('update jobs failed, error: {}'.format(str(e)))

if __name__ == "__main__":
	if len(sys.argv) == 1:
		sys.exit('please specify the yaml file path which want to update and the update test mode<deployment|performance>.')
	if len(sys.argv) == 2:
		sys.exit('please specify the update test mode<deployment|performance>.')
	if len(sys.argv) == 3:
		fpath = sys.argv[1]
		mode = sys.argv[2]

	if not os.path.exists(fpath):
		sys.exit('{} is not exits'.format(fpath))

	if mode != 'deployment' and mode != 'performance':
		sys.exit('{} is not a recognized mode, "deployment" or "performance" is allowed.'.format(mode))

	base_name = os.path.basename(fpath)
	dir_name = os.path.dirname(fpath)
	new_file_path = os.path.join(dir_name, 'new_' + base_name)
	print('save updated file as {}'.format(new_file_path))

	if base_name == 'bosh.yml':
		updatebosh(fpath, new_file_path, mode)
	elif base_name == 'multiple-vm-cf.yml':
		updatecf(fpath, new_file_path, mode)

