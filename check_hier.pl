#!/home/utils/perl-5.8.8/bin/perl 

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use Cwd;
use Spreadsheet::ParseExcel;
use Spreadsheet::WriteExcel;


my $hier_info;
my $severity;
my $live;
my $input_cm_hier;
my $output_cm_hier;
my $changelist;
my $prefix="WRAP.top_wrap.u_nv_top";
my $TOT = `depth`;
my $testplan_dir = $TOT."/regression/nextp/system_testplans";
my $xls_file = $TOT."/../ar/doc/t210/soc_verif/SocTop/toggle_hier_ownership.xls";
my $waive_dir = $TOT."/dvlib/coverage/sys/toggle/toggle_waive";
my $modules = {};
my $owners = {};
my $tree = {};
my $storage_book={};
my $analysis = {};
my $en_warning = 1;
my $debug = 0;

GetOptions("hier_info=s",\$hier_info,
           "severity:i",\$severity,
           "live:i",\$live,
           "input_cm_hier:s",\$input_cm_hier,
           "output_cm_hier:s",\$output_cm_hier,
           "changelist:s",\$changelist,
           );
#&initOneTreeBranch($tree,"ccplex0_0.fccplex.fcluster","");
#&initOneTreeBranch($tree,"ccplex0_0.fccplex.fcluster.fcpu1","");
#&initOneTreeBranch($tree,"ccplex0_0.sccplex.scluster.scpu0","");
#
#&getPointerByInst($tree,"ccplex0_0.sccplex.scluster.scpu0")->{"owner"} ="rovluo";
#print Dumper %$tree;
#&cutTree($tree);
#print Dumper %$tree;
#exit;

&initModules($modules,$hier_info);

&initOwnership($owners,$modules,$tree) if(!$input_cm_hier);
&dumpIntermediateData("tmp",$tree,1);

&genCmhier($modules,$input_cm_hier,$output_cm_hier) if($output_cm_hier);

&cutTree($tree) if($changelist);

&updateXls($storage_book,$xls_file,"out.xls") if($changelist);

&dumpIntermediateData("tmp",$modules);
&dumpIntermediateData("tmp",$tree);
&dumpIntermediateData("tmp",$owners);
&dumpIntermediateData("tmp",$storage_book);
&dumpIntermediateData("tmp",$analysis);

sub cutTree() {
	my ($inst_p) = @_;
	my $counter = 0;
	my $instnum = 0;
	my $owner;

	if($inst_p->{"owner"}) {
		$inst_p->{"instances"} = undef;
		return 1;
	}

	foreach (keys %{$inst_p->{"instances"}}) {
		$counter += &cutTree($inst_p->{"instances"}->{$_});
	}

	$instnum = scalar(keys %{$inst_p->{"instances"}});

	if(!$counter) {
		foreach (keys %{$inst_p->{"instances"}}) {
			$owner = $inst_p->{"instances"}->{$_}->{"owner"};
			if(!$owner) {}
			elsif($owner eq "PART") {$inst_p->{"owner"} = "PART";return 0;}
			else {die "illegal instance owner: $_:$owner\n"}
		}
		$inst_p->{"instances"} = undef;
	}
	elsif($counter < $instnum) {
		$inst_p->{"owner"} = "PART";
	}
	elsif($counter == $instnum) {
		$inst_p->{"owner"} = "ALL";
		$inst_p->{"instances"} = undef;
		return 1;
	}
	else{
		die;
	}
	
	return 0;
}

sub genCmhier() {
	my ($modules,$input_cm_hier,$output_cm_hier) = @_;
	my $hiers = [];
	my $module;
	my $waive_file;
	if($input_cm_hier) {
		open IHFH ," <$input_cm_hier" or die "Could not open $input_cm_hier: $!";
		while(my $line = <IHFH>) {
			if ( $line =~ /\+module\s+(\w+)/) {
				@$hiers = (@$hiers,$1);
			}
		}
		close IHFH;
	}
	else {
		foreach $module (keys %$modules) {
			if($modules->{$module}->{"owner"}) {
				@$hiers = (@$hiers,$module);
			}
		}
	}

	open OHFH, ">$output_cm_hier" or die "Could not open $output_cm_hier: $!";
	foreach $module (@$hiers) {
		if(exists $modules->{$module}) {
			$waive_file = $modules->{$module}->{"waivefile"};
		} else {
			$waive_file = "$waive_dir/$module.toggle_waive";
			print qq/WARNING: Module ($module) in $input_cm_hier is not existent.\n/ if($en_warning);
		}
		print OHFH "+module $module"."\n";
		if($waive_file && -s $waive_file) {
			open WFH ," <$waive_file" or die "Could not open $waive_file: $!";
			while(my $line = <WFH>) {
				chomp $line;
				$line =~ s/#.*//;
				$line =~ s/\s//g;
				next if(!$line);
				die "illegal character sequence in $waive_file.\nline content: $line\nFor details please refer to https://wiki.nvidia.com/wmpwiki/index.php/Shanghai/Mobile/Shanghai_Mobile_SOCV_Infra_Team/toggle_flow#Waive_signals" if (&checkSignal($line));
				if($line =~ /\./) {
					print OHFH "  -node $line"."\n";
				}
				else {
					print OHFH "  -node $module.$line"."\n";
				}
			}
			close WFH;
		}
	}
	close OHFH;
}

sub checkSignal {
	my ($line) = @_;
	my $illegal = 0;
	$illegal += 1 if($line =~ /[^0-9a-zA-Z_\.\+\?\*]/);
	$illegal += 1 if($line =~ /\.(\*|\+|\?)/);
	return $illegal;
}

sub updateXls() {
	# cobbled together from examples for the Spreadsheet::ParseExcel and
	# Spreadsheet::WriteExcel modules
	my ($storage_book,$sourcename,$destname) = @_;
	my $source_excel = new Spreadsheet::ParseExcel;
	my $source_book = $source_excel->Parse($sourcename) or die "Could not open source Excel file $sourcename: $!";
	my $module;
	my $row_index = 0;	#row_index used in storage_book while $row is temporary variable
	my $maxcol;
	my $instances;
	my $counter;
	
	print "Reading data from $sourcename...\n";
	foreach my $source_sheet_number (0 .. 0) #$source_book->{SheetCount}-1)
	{
		my $source_sheet = $source_book->{Worksheet}[$source_sheet_number];
		print "--------- SHEET:", $source_sheet->{Name}, "\n";
		# sanity checking on the source file: rows and columns should be sensible
		next unless defined $source_sheet->{MaxRow};
		next unless $source_sheet->{MinRow} <= $source_sheet->{MaxRow};
		next unless defined $source_sheet->{MaxCol};
		next unless $source_sheet->{MinCol} <= $source_sheet->{MaxCol};
		$maxcol = $source_sheet->{MaxCol};
		foreach my $row ($source_sheet->{MinRow} .. $source_sheet->{MaxRow})
		{
			# | Module name | Ownership(test plan) | Instances | Port number | Waive location(if exists) | Changelist | Waive(bug or signoff person required) |
			if(!$row) {
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"0"} = "Module name";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"1"} = "Ownership(test plan)";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"2"} = "Instances";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"3"} = "Port number";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"4"} = "Comments";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"5"} = "Changelist";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"6"} = "Module file";
				$storage_book->{$source_sheet->{Name}}->{$row_index}->{"7"} = "Signal waive file";
				$row_index++;
				next;
			}
			$module = $source_sheet->{Cells}[$row][0]->{Val};
			if(exists $modules->{$module}) {
				$modules->{$module}->{"customm"} = $source_sheet->{Cells}[$row][4]->{Val};
				$modules->{$module}->{"portnumber"} = $source_sheet->{Cells}[$row][3]->{Val} if(!$live);
			}
		} # foreach row
		foreach $module (sort keys %$modules) {
			next if $modules->{$module}->{"notdump"};
			$instances=[];$counter=0;
			foreach(keys %{$modules->{$module}->{"instances"}}) {
				if($modules->{$module}->{"owner"}) {$instances->[$counter++] = $_;next;} #write all instances of module which owned by somebody to report
				if(&getPointerByInst($tree,$_)) {$instances->[$counter++] = $_;}
			}
			next if(!scalar(@$instances) && !$modules->{$module}->{"owner"});
			$analysis->{"modulenum"}->[0] += 1;
			$analysis->{"instancenum"}->[0] += scalar(@$instances);
			$analysis->{"portnum"}->[0] += $modules->{$module}->{"portnumber"};
			if($modules->{$module}->{"owner"}) {
				$analysis->{"modulenum"}->[1] += 1;
				$analysis->{"instancenum"}->[1] += scalar(@$instances);
				$analysis->{"portnum"}->[1] += $modules->{$module}->{"portnumber"};
			}
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"0"} = $module;
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"1"} = $modules->{$module}->{"owner"};
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"2"} = join ("\n",@$instances);
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"3"} = $modules->{$module}->{"portnumber"};
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"4"} = $modules->{$module}->{"customm"};
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"5"} = $changelist;
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"6"} = $modules->{$module}->{"deffile"};
			$storage_book->{$source_sheet->{Name}}->{$row_index}->{"7"} = $modules->{$module}->{"waivefile"};
			$row_index++;
		}
	} # foreach source_sheet_number
	#print "Perl recognized the following data (sheet/row/column order):\n";
	#print Dumper $storage_book;
	my $dest_book  = Spreadsheet::WriteExcel->new("$destname") or die "Could not create a new Excel file in $destname: $!";
	print "Saving recognized data in $destname...";
	foreach my $sheet (keys %$storage_book)
	{
		my $dest_sheet = $dest_book->addworksheet($sheet);
		$dest_sheet->set_column(0, 0, 30);
		$dest_sheet->set_column(1, 1, 15);
		$dest_sheet->set_column(2, 2, 60);
		$dest_sheet->set_column(3, 3, 10);
		$dest_sheet->set_column(4, 4, 20);
		$dest_sheet->set_column(5, 5, 10);
		$dest_sheet->set_column(6, $maxcol, 60);
		$dest_sheet->autofilter(0, 0, 0, $maxcol);
		$dest_sheet->freeze_panes(1, 0);
		foreach my $row (keys %{$storage_book->{$sheet}})
		{
			my $rowStyle = $dest_book->add_format();
			$rowStyle->set_text_wrap();
			if($row % 2) {$rowStyle->set_bg_color('silver');}
			foreach my $col (keys %{$storage_book->{$sheet}->{$row}})
			{
				$dest_sheet->write($row, $col, $storage_book->{$sheet}->{$row}->{$col}, $rowStyle);
			} # foreach column
		} # foreach row
	} # foreach sheet
	$dest_book->close();
	print "done!\n";
}

sub trvModulePort {
	my ($deffile) = @_;
	my $counter = 0;;
	$deffile =~ s/^.*\/hw\/ap/$TOT/;
	open MFH ," <$deffile" or return -1;

	#input    [5:0] i_dfll_regs_dfll_output_config_div_d;
	while (<MFH>) {
		if(/^\s*(input|output|inout)\s*(\[\d+:\d+\])?\s*(\w+)\s*;/) {
			$counter++;
		}
	}
	close MFH;
	return $counter;
}

sub initModules {
	my ($modules,$hier_info) = @_;
	my $instance;
	my $module_file;
	my $module;
	my $waive_file;
	my @array;

	open HIFH ," <$hier_info" or die "Could not open $hier_info: $!";
	while(my $line = <HIFH>) {
		if ( $line =~ /FINFO:$prefix\.(.+)=(.+)$/) {
			$instance = $1;
			$module_file = $2;
			@array = split(/\//,$module_file);$module = pop(@array);
			@array = split(/\./,$module);$module = shift(@array);

			next if($instance =~ /\\/);
			#print "$module:$instance\n";
			if (!exists $modules->{$module}) {
				next unless($module_file =~ /\/(vmod|vlib)\//);
				$modules->{$module}->{"deffile"} = $module_file;
				$modules->{$module}->{"portnumber"} = $live?&trvModulePort($module_file):-1;
				$modules->{$module}->{"owner"} = "";
				$modules->{$module}->{"notdump"} = 0;#whether pushed into storage_book or not
				$modules->{$module}->{"customm"} = "";
			}
			$modules->{$module}->{"instances"}->{$instance} = "";
			$waive_file = "$waive_dir/$module.toggle_waive";
			if ( -f $waive_file ) {
				$modules->{$module}->{"waivefile"} = $waive_file;
			}
			else {
				$modules->{$module}->{"waivefile"} = "";
			}
		}
	}
	close HIFH;
}

sub getPointerByInst() {
	my ($inst_pp,$instance) = @_;
	my $hiernum = &getHierNum($instance);
	my $inst_p={};

	if(!($inst_p = $inst_pp->{"instances"}->{&getSubHier($instance,0,0)})) {
		return undef;
	}
		
	if($hiernum > 1) {
		return &getPointerByInst($inst_p,&getSubHier($instance,1,-1));
	}
	elsif ($hiernum == 1) {
		return $inst_p;
	}
	else {
		die;
	}

}

sub initOneTreeBranch() {
	my ($inst_pp,$instance,$owner) = @_;
	my $hiernum = &getHierNum($instance);
	my $inst_p = {};

	if(exists $inst_pp->{"instances"}->{&getSubHier($instance,0,0)}) {
		$inst_p = $inst_pp->{"instances"}->{&getSubHier($instance,0,0)};
	}

	if($hiernum > 1) {
		&initOneTreeBranch($inst_p, &getSubHier($instance,1,-1),$owner)
	}
	elsif ($hiernum == 1) {
		#die "duplicate leaf inst:$instance\n" if(exists $inst_pp->{"instances"}->{$instance});
		$inst_p->{"owner"} = $owner;
	}
	else {
		die;
	}

	$inst_pp->{"instances"}->{&getSubHier($instance,0,0)} = $inst_p;
	print Dumper %$inst_pp if($debug);
}

sub getHierNum() {
	my ($instance) = @_;
	$instance =~ s/[^\.]//g;
	return (length($instance)+1);
}

#0,1,2...-1
sub getSubHier() {
	my ($instance,$begin,$end) = @_;
	my $hiernum = &getHierNum($instance);
	my @array;

	die $! if(!defined($begin) || !defined($end));

	$begin = ($begin + $hiernum)%$hiernum if($begin<0);
	$end = ($end + $hiernum)%$hiernum if($end<0);
	print "getSubHier $instance($hiernum) [$begin,$end]" if($debug);

	die $! if((0 > $begin) || ($begin > $end) || ($end >= $hiernum));

	@array = split(/\./,$instance);
	splice(@array, $end+1, $hiernum - 1) if($hiernum - 1 - $end);
	splice(@array, 0, $begin) if($begin);
	$instance = join(".", @array);
	print " = $instance\n" if($debug);
	return $instance;
}

sub initOwnership() {
	my ($owners,$modules,$tree) = @_;
	my $file;
	my @array;
	my $testplan;
	my $module;
	my $counter=0;

	opendir DIR, $testplan_dir or die "Could not open $testplan_dir: $!";
	while ($file = readdir DIR) {
		next unless $file =~ /\.py/;
		@array = split(/\./,$file);
		$testplan = shift(@array);
		open TPFH ," <$testplan_dir/$file" or die "Could not open $testplan_dir/$file: $!";

		#'owned_rtl_modules': ['xbar_iram_ctlr', 'NV_iram_wrapper', 'xbar_decoder', 'xbarmux_iram', 'xbarmux_arm', 'NV_exp_vectors', 'NV_apc_to_arm7', 'xbar_apb_ctlr' ],'contributed_rtl_modules': []}
		while (<TPFH>) {
			if (/owned_rtl_modules/ && !/^\s*\#/) {
				m/\[([^\[\]]*)\]/;
				@array = split (/[', ]+/,$1);
				foreach $module (@array) {
					next unless ($module);
					if(!exists $modules->{$module}) {
						print qq/WARNING: Module ($module) in $file is not existent.\n/ if($en_warning);
						$counter +=1;
					}
					if(!exists $owners->{$module}) {
						$owners->{$module} = $testplan;
					} else {
						print qq/WARNING: Two testplans ($owners->{$module},$testplan) own the same module ($module)\n/ if($en_warning);
						$counter +=1;
					}
				}
				last;
			}
		}
		close TPFH;
	}
	close DIR;
	die "ERROR:$counter warnings occured when check all testplans" if($counter && $severity);

	$owners->{"NV_d_ccplex0"} = "ccplex";
	$owners->{"NV_d_gpu0"} = "gpu";

	foreach $module (keys %$modules) {
		if (exists $owners->{$module}) {
			$modules->{$module}->{"owner"} = $owners->{$module};
		}
		else {
			$modules->{$module}->{"owner"} = "";
		}
		foreach (keys %{$modules->{$module}->{"instances"}}) {
			&initOneTreeBranch($tree,$_,$modules->{$module}->{"owner"});
		}
	}
}

#record intermedia data to temporary file for debug
sub dumpIntermediateData() {
	my ($file,$hash,$first) = @_;
	if($first) {
		open RCDFH ,">$file" or die "Could not open $file: $!";
	}
	else {
		open RCDFH ,">>$file" or die "Could not open $file: $!";
	}
	print RCDFH "==========$hash:==========\n";
	print RCDFH Dumper(%$hash);
	close RCDFH;
}

0;
