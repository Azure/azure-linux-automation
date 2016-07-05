import os.path
import sys

bosh_log = "deploy_bosh_test.log"
cf_log = "deploy_cf_test.log"

def caltime(total, *args):
	(h,m,s) = total.split(':')
	total_s = int(h)*60*60 + int(m)*60 + int(s)
	cost_s=0
	for i in args:
		(h,m,s) = i.split(':')
		cost_s += int(h)*60*60 + int(m)*60 + int(s)
	left_s = total_s - cost_s
	sec = left_s%60
	mmin = left_s/60
	if mmin >= 60:
		hr = mmin/60
		min_add = mmin%60
		mmin = mmin + min_add
	else:
		hr = 0

	def fn(num):
		if num == 0:
			num = '00'
		elif len(str(num)) == 1:
			num = '0'+str(num)
		else:
			num = str(num)
		return num
		
	return ':'.join(map(fn, [hr, mmin, sec]))

def parseboshlog():
	if os.path.exists(bosh_log):
		with open(bosh_log) as f:
			l = f.readlines()
		for i in l:
			if 'Finished validating' in i:
				print('deploy_bosh_validate={}'.format(i.split()[-1][1:-1]))
			if 'Finished installing CPI' in i:
				print('deploy_bosh_install_cpi={}'.format(i.split()[-1][1:-1]))
			if 'Uploading stemcell' in i and 'Finished' in i:
				print('deploy_bosh_upload_stemcell={}'.format(i.split()[-1][1:-1]))
			if 'Finished deploying' in i:
				print('deploy_bosh_deploy={}'.format(i.split()[-1][1:-1]))
			if 'real' in i:
				print('deploy_bosh_total={}'.format(i.split()[-1]))			
	else:
		print('deploy_bosh_log_not_found')

def parsecflog():
	if os.path.exists(cf_log):
		with open(cf_log) as f:
			l = f.readlines()
		tasks_duration = [] # sequence 3 tasks
		for i in l:
			if 'Duration' in i:
				tasks_duration.append(i.split()[-1])
			if 'Done compiling packages' in i and not '>' in i:
				t_compile = i.split()[-1][1:-1]
				print('deploy_cf_compile_packages={}'.format(t_compile))
			if 'Done creating missing vms' in i and not '>' in i:
				t_createvm = i.split()[-1][1:-1]
				print('deploy_cf_create_vms={}'.format(t_createvm))
			if 'real' in i:
				print('deploy_cf_total={}'.format(i.split()[-1]))
		print('deploy_cf_upload_stemcell={}'.format(tasks_duration[0]))
		print('deploy_cf_release_upload={}'.format(tasks_duration[1]))
		print('deploy_cf_update_jobs={}'.format(caltime(tasks_duration[2], t_compile, t_createvm)))
	else:
		print('deploy_cf_log_not_found')	

if __name__ == '__main__':
	if len(sys.argv) == 1:
		print("specify 'bosh' or 'cf' as argument")
	elif sys.argv[1] == 'bosh':
		parseboshlog()
	elif sys.argv[1] == 'cf':
		parsecflog()
	else:
		print('unknown selector argument')
